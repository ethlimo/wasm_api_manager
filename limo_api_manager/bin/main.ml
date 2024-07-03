open Extism
open Cohttp
open Cohttp_eio
open Ppx_yojson_conv_lib.Yojson_conv.Primitives
open Lib.Dweb_api_response
open Lib.Http_types
open Lib.Http_string

let port = ref 8000

let () = Logs.set_reporter (Logs_fmt.reporter ())
and () = Logs.Src.set_level Cohttp_eio.src (Some Debug)
and () = Logs.Src.set_level Logs.default (Some Debug)

let log_warning str = Logs.warn (fun f -> f "%s" str)
let log_error ex = Logs.err (fun f -> f "%a" Eio.Exn.pp ex)
let log_exn_as_warning ex = Logs.err (fun f -> f "%a" Eio.Exn.pp ex)
let log_info str = Logs.info (fun f -> f "%s" str)

let url_of_server = "http://127.0.0.1:3000"

let ensure_string_has_trailing_slash (s : string) : string =
  let rec remove_trailing_slash s =
    if String.length s > 0 && s.[String.length s - 1] = '/' then
      remove_trailing_slash (String.sub s 0 (String.length s - 1))
    else
      s
  in
  let trimmed_string = String.trim s in
  let trimmed_string_without_slash = remove_trailing_slash trimmed_string in
  if String.length trimmed_string_without_slash > 0 then
    trimmed_string_without_slash ^ "/"
  else
    trimmed_string_without_slash

module WasmRepository = struct
  type ensname = string
  type artifactname = string
  type wasm_payload = string
  type artifact = Extism.Plugin.t
  type user_table = { artifact_table : (artifactname, artifact) Hashtbl.t }
  type tbl = (ensname, user_table) Hashtbl.t
  type t = {
    table : tbl;
    httpClient: Client.t;
  }

  let get_table_from_ensname (t : t) (ensname : ensname) :
      (artifactname, artifact) Hashtbl.t =
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

  let create (env) : t =
    let tbl = Hashtbl.create 10 in
    { table = tbl; httpClient = Client.make ~https:(Some https) env#net }

  let get_url_of_ensname (t: t) (sw: Eio.Std.Switch.t) (ensname : ensname) : string option =
    let uri = Uri.of_string url_of_server in
    let headers = Header.add_list (Header.init_with "Accept" "application/json") [("Host", ensname)] in
    let resp, body = Client.get ~headers t.httpClient ~sw uri in
    if Http.Status.compare resp.status `OK = 0 then
      let body = Eio.Buf_read.(parse_exn take_all) body ~max_size:max_int in
      let json = Yojson.Safe.from_string body in
      let response = dweb_api_response_of_yojson json in
      Some ((ensure_string_has_trailing_slash response.x_content_location) ^ response.x_content_path)
    else
      None


  let get_artifacts_of_ensname (_ensname : ensname) : artifactname array =
    [| "router.wasm" |]

  let get_artifact_url_of_ensname (t: t) (sw: Eio.Std.Switch.t) (ensname : ensname)
      (artifactname : artifactname) : string option =
    let base_url = get_url_of_ensname t sw ensname in
    Option.map (fun x -> (ensure_string_has_trailing_slash x) ^ artifactname ^ ".wasm") base_url
end

let download_wasm_payload (wasm_repository : WasmRepository.t) (sw: Eio.Std.Switch.t) (ensname : string)
    (artifactname : string) : Extism.Plugin.t option =
  let artifact =
    WasmRepository.get_artifact_url_of_ensname wasm_repository sw ensname artifactname
  in
  Option.map (fun x -> 
  let wasm = Manifest.Wasm.url x in
  let manifest = Manifest.create [wasm] in
  let plugin = Plugin.of_manifest_exn ~wasi:true manifest in
  log_info (Printf.sprintf "Loaded plugin %s from %s\n" ensname x);
  plugin) artifact

let get_wasm_payload (wasm_repository : WasmRepository.t) (sw: Eio.Std.Switch.t) (ensname : string)
    (artifactname : string) : Extism.Plugin.t option =
  let table = WasmRepository.get_table_from_ensname wasm_repository ensname in
  match Hashtbl.find_opt table artifactname with
  | Some x -> Some x
  | None ->
      let plugin = download_wasm_payload wasm_repository sw ensname artifactname in
      Option.iter (fun x -> Hashtbl.replace table artifactname x) plugin;
      plugin

let server env sw =
  let wasm_repository = WasmRepository.create env in
  let callback _conn req (body : Cohttp_eio.Server.body) =
    let url = req |> Request.uri in
    let path = Uri.path url in
    let query = List.map http_query_of_uri_query @@ Uri.query url in
    let meth = req |> Request.meth |> Code.string_of_method in
    let headers =
      req |> Request.headers |> Header.to_string |> String.split_on_char '\n'
    in
    ( body |> Eio.Flow.read_all )
    |> fun body -> 
      let request = Yojson.Safe.to_string (yojson_of_http_request {url = (Uri.to_string url); method_ = meth; headers; body; path; query; }) in
      log_info (Printf.sprintf "Request: %s" request);
      let manifest = get_wasm_payload wasm_repository sw "vitalik.eth" "router" in
      match manifest with
      | Some plugin ->
        let response = http_response_of_json_string @@ Extism.Error.unwrap @@ Plugin.call_string plugin ~name:"http_json" (request) in
        let warn_bad_headers = fun x -> log_warning (Printf.sprintf "Bad header: %s" x) in
        let response_headers = Http.Header.of_list @@ remove_bad_headers response.headers ~bad_header_log_function:(Some warn_bad_headers) in
        Server.respond_string ~headers:response_headers ~status:Http.Status.(`Code response.statusCode) ~body:response.body ()
      | None -> Server.respond_string ~status:Http.Status.(`Not_found) ~body:"" ()
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
