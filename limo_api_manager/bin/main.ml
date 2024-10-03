open Extism
open Cohttp
open Cohttp_eio
open Ppx_yojson_conv_lib.Yojson_conv.Primitives
open Lib.Dweb_api_response
open Lib.Http_types
open Lib.Http_string
open Lib.Wasm_repository
open Lib.Http_client

let log_info = Lib.Utils.log_info
let log_warning = Lib.Utils.log_warning
let log_error = Lib.Utils.log_error
let log_exn_as_warning = Lib.Utils.log_exn_as_warning

let port = ref 8000
let domain_suffix = ref None
let domain_suffix_replacement = ref None

let () = Logs.set_reporter (Logs_fmt.reporter ())
and () = Logs.Src.set_level Cohttp_eio.src (Some Debug)
and () = Logs.Src.set_level Logs.default (Some Debug)

let extract_host_header domain_replacement_list headers =
  match Header.get headers "host" with
  | Some host -> Lib.Utils.replace_domain_suffix domain_replacement_list host
  | None ->
    log_warning "Host header is missing";
    failwith "Host header is missing"

let server (env) (sw) domain_replacement_list =
  let (module Client) = make_cohttpeioclient env#net in
  let (module WPD) = make_wasmPayloadDownloader () in
  let module WR = WasmRepository(Client)(WPD) in
  let repo = WR.create () in
  let callback _conn req (body : Cohttp_eio.Server.body) =
    let url = req |> Request.uri in
    let path = Uri.path url in
    let query = List.map http_query_of_uri_query @@ Uri.query url in
    let meth = req |> Request.meth |> Code.string_of_method in
    let headers = req |> Request.headers in
    let host_header = extract_host_header domain_replacement_list headers in
    let new_headers = Header.replace headers "host" host_header in
    ( body |> Eio.Flow.read_all ) |> fun body ->
      let request = Yojson.Safe.to_string (yojson_of_http_request {url = (Uri.host_with_default url); method_ = meth; headers = (new_headers |> Header.to_string |> String.split_on_char '\n'); body; path; query; }) in
      log_info (Printf.sprintf "Request: %s" request);
      let manifest = WR.get_router repo sw host_header false in
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

let speclist = [
  ("--port", Arg.Set_int port, "Port to listen on");
  ("--domain-suffix", Arg.String (fun s -> domain_suffix := Some s), "Domain suffix");
  ("--domain-suffix-replacement", Arg.String (fun s -> domain_suffix_replacement := Some s), "Domain suffix replacement")
]

let () =
  Arg.parse speclist (fun _ -> ()) "";
  if !port < 1 || !port > 65535 then
    failwith "Invalid port number";
  let domain_replacement_list = Lib.Utils.create_domain_replacement_list [(!domain_suffix, !domain_suffix_replacement)] in
  Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw -> Mirage_crypto_rng_eio.run (module Mirage_crypto_rng.Fortuna) env @@ fun _ -> server env sw (Option.value domain_replacement_list ~default:[])
