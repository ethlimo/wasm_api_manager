open Extism
open Cohttp
open Cohttp_eio
open Ppx_yojson_conv_lib.Yojson_conv.Primitives
let port = ref 8000

let () = Logs.set_reporter (Logs_fmt.reporter ())
and () = Logs.Src.set_level Cohttp_eio.src (Some Debug)
and () = Logs.Src.set_level Logs.default (Some Debug)

let log_warning str = Logs.warn (fun f -> f "%s" str)
let log_error ex = Logs.err (fun f -> f "%a" Eio.Exn.pp ex)
let log_exn_as_warning ex = Logs.err (fun f -> f "%a" Eio.Exn.pp ex)
let log_info str = Logs.info (fun f -> f "%s" str)

(* let wasm = Manifest.Wasm.url "https://github.com/extism/plugins/releases/latest/download/count_vowels.wasm"
   let manifest = Manifest.create [wasm]
   let plugin = Plugin.of_manifest_exn manifest *)

module WasmRepository = struct
  type ensname = string
  type artifactname = string
  type wasm_payload = string
  type user_table = { artifact_table : (artifactname, string) Hashtbl.t }
  type tbl = (ensname, user_table) Hashtbl.t
  type t = {
    table : tbl;
  }

  let get_table_from_ensname (t : t) (ensname : ensname) :
      (artifactname, string) Hashtbl.t =
    match Hashtbl.find_opt (t.table) ensname with
    | Some x -> x.artifact_table
    | None ->
        let newTbl = Hashtbl.create 1 in
        Hashtbl.replace (t.table) ensname { artifact_table = newTbl };
        newTbl

  let https =
    let authenticator =
      match Ca_certs.authenticator () with
      | Ok x -> x
      | Error msg -> (
          match msg with
          | `Msg x ->
              failwith (Format.asprintf "Failed to load CA certificates: %s" x))
    in

    let tls_config = Tls.Config.client ~authenticator () in
    fun uri raw ->
      let host =
        Uri.host uri
        |> Option.map (fun x -> Domain_name.(host_exn (of_string_exn x)))
      in
      Tls_eio.client_of_flow ?host tls_config raw

  let create : t =
    let tbl = Hashtbl.create 10 in
    { table = tbl }

  let get_url_of_ensname (_ensname : ensname) : string =
    "http://127.0.0.1:3000"

  let get_artifacts_of_ensname (_ensname : ensname) : artifactname array =
    [| "router.wasm" |]

  let get_artifact_url_of_ensname (ensname : ensname)
      (artifactname : artifactname) : string =
    let base_url = get_url_of_ensname ensname in
    base_url ^ "/" ^ artifactname ^ ".wasm"
end

let get_wasm_payload (wasm_repository : WasmRepository.t) (net: _ Eio.Net.t) (sw: Eio.Std.Switch.t) (ensname : string)
    (artifactname : string) : Extism.Plugin.t =
  let artifact =
    WasmRepository.get_artifact_url_of_ensname ensname artifactname
  in
  let wasm = Manifest.Wasm.url artifact in
  let manifest = Manifest.create [wasm] in
  let plugin = Plugin.of_manifest_exn ~wasi:true manifest in
  plugin

type http_request = {
  url : string;
  method_ : string; [@key "method"]
  headers : string list;
  body : string;
}
[@@deriving yojson]

type http_response = {
  statusCode : int;
  headers : string list;
  body : string;
}
[@@deriving yojson]

type parsed_header = GoodHeader of (string * string) | BadHeader of string

let strip_header_whitespace header =
  let len = String.length header in
  let rec strip_whitespace i =
    if i >= len then ""
    else if header.[i] = ' ' then strip_whitespace (i + 1)
    else String.sub header i (len - i)
  in
  strip_whitespace 0

let header_string_to_header_tuple header =
  let header_list = String.split_on_char ':' header in
  match header_list with
  | [ key; value ] -> GoodHeader (String.lowercase_ascii key, strip_header_whitespace value)
  | _ -> BadHeader header

let remove_bad_headers headers ?(bad_header_log_function = None) =
  let parsed_headers = List.map header_string_to_header_tuple headers in
  let good_headers = List.filter_map (function
    | GoodHeader x -> Some x
    | BadHeader x -> (
        match bad_header_log_function with
        | Some f -> f x; None
        | None -> None))
    parsed_headers
  in
  good_headers

let http_response_of_json_string json_str =
  let json = Yojson.Safe.from_string json_str in
  let response = http_response_of_yojson json in
  response

let server env sw =
  let wasm_repository = WasmRepository.create in
  let plugin = (Eio.Switch.run (fun sw -> get_wasm_payload wasm_repository env#net sw "vitalik.eth" "router")) in
  Printf.printf "Plugin: %b" (Plugin.function_exists plugin "http_json");
  let callback _conn req (body : Cohttp_eio.Server.body) =
    let url = req |> Request.uri |> Uri.to_string in
    let meth = req |> Request.meth |> Code.string_of_method in
    let headers =
      req |> Request.headers |> Header.to_string |> String.split_on_char '\n'
    in
    ( body |> Eio.Flow.read_all )
    |> fun body -> 
      let request = Yojson.Safe.to_string (yojson_of_http_request {url; method_ = meth; headers; body }) in
      log_info (Printf.sprintf "Request: %s" request);
      let manifest = get_wasm_payload wasm_repository env#net sw "vitalik.eth" "router" in
      let response = http_response_of_json_string @@ Extism.Error.unwrap @@ Plugin.call_string manifest ~name:"http_json" (request) in
      let warn_bad_headers = fun x -> log_warning (Printf.sprintf "Bad header: %s" x) in
      let response_headers = Http.Header.of_list @@ remove_bad_headers response.headers ~bad_header_log_function:(Some warn_bad_headers) in

      Server.respond_string ~headers:response_headers ~status:Http.Status.(`Code response.statusCode) ~body:response.body ()
  in
  let socket =
    Eio.Net.listen env#net ~sw ~backlog:128 ~reuse_addr:true
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, !port))
  in

  Cohttp_eio.Server.run socket
    (Cohttp_eio.Server.make ~callback ())
    ~on_error:log_exn_as_warning

let () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw -> server env sw
