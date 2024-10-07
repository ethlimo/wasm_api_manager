open Dweb_api_response
open Http_client

let log_info = Utils.log_info
let log_warning = Utils.log_warning
let log_error = Utils.log_error
let log_exn_as_warning = Utils.log_exn_as_warning

let ensure_string_has_trailing_slash (s : string) : string =
  let rec remove_trailing_slash s =
    if String.length s > 0 && s.[String.length s - 1] = '/' then
      remove_trailing_slash (String.sub s 0 (String.length s - 1))
    else s
  in
  let trimmed_string = String.trim s in
  let trimmed_string_without_slash = remove_trailing_slash trimmed_string in
  if String.length trimmed_string_without_slash > 0 then
    trimmed_string_without_slash ^ "/"
  else trimmed_string_without_slash

type ensname = string

module type WasmPayloadDownloader = sig
  val get_artifacts_as_bytes_base64 :
    (module HttpClient)  -> Eio.Std.Switch.t -> Uri.t -> ensname -> string option
end

let make_wasmPayloadDownloader () : (module WasmPayloadDownloader) =
  let module WPD = struct
    let get_artifacts_as_bytes_base64 (module CT : HttpClient)
        (sw : Eio.Std.Switch.t) (dweb_api_server: Uri.t) (ensname : ensname) : string option =
      let get_url_of_ensname (client : CT.t) (sw : Eio.Std.Switch.t)
          (ensname : ensname) : string option =
        let headers = [ ("Host", ensname); ("Accept", "application/json") ] in
        let resp, body = CT.get client ~headers sw dweb_api_server in
        log_info (Printf.sprintf "%s: get_url_of_ensname response status: %s\n" ensname
          (Cohttp.Code.string_of_status (Cohttp.Response.status resp)));
        if Cohttp.Response.status resp = `OK then
          let json = Yojson.Safe.from_string body in
          let response = dweb_api_response_of_yojson json in
          Some
            (ensure_string_has_trailing_slash response.x_content_location
            ^ response.x_content_path)
        else None
      in

      let get_artifact_url_of_ensname client sw ensname artifactname :
          string option =
        let base_url = get_url_of_ensname client sw ensname in
        Option.map
          (fun x -> ensure_string_has_trailing_slash x ^ artifactname ^ ".wasm")
          base_url
      in

      let get_wasm_payload client sw ensname artifactname =
        let url = get_artifact_url_of_ensname client sw ensname artifactname in
        match url with
        | Some url ->
            let headers =
              [ ("Host", ensname); ("Accept", "application/json") ]
            in
            let resp, body = CT.get client ~headers sw (Uri.of_string url) in
            log_info (Printf.sprintf "%s: get_wasm_payload %s response status: %s\n" ensname artifactname
              (Cohttp.Code.string_of_status (Cohttp.Response.status resp)));
            if Cohttp.Response.status resp = `OK then
              Some body
            else None
        | None -> None
      in
      let client = CT.create () in
      get_wasm_payload client sw ensname "router"
  end in
  (module WPD : WasmPayloadDownloader)

type 'a cache_report = {
  data: 'a;
  from_cache: bool;
}

let hashtable_remove_all_by_key (tbl : ('a, 'b) Hashtbl.t) (key : 'a) : unit =
  let rec remove_all_by_key tbl key =
    match Hashtbl.find_opt tbl key with
    | Some _ -> (
        Hashtbl.remove tbl key;
        remove_all_by_key tbl key)
    | None -> ()
  in
  remove_all_by_key tbl key

module WasmRepository (CT : HttpClient) (WPD: WasmPayloadDownloader) = struct
  type artifactname = string
  type wasm_payload = string
  type artifact = Extism.Plugin.t
  type user_table = { artifact_table : (artifactname, artifact) Hashtbl.t }
  type tbl = (ensname, user_table) Hashtbl.t
  type t = { table : tbl }

  let get_table_from_ensname (t : t) (ensname : ensname) :
      (artifactname, artifact) Hashtbl.t =
    match Hashtbl.find_opt t.table ensname with
    | Some x -> x.artifact_table
    | None ->
        let newTbl = Hashtbl.create 1 in
        Hashtbl.replace t.table ensname { artifact_table = newTbl };
        newTbl

  let create () : t =
    let tbl = Hashtbl.create 10 in
    { table = tbl }
  let get_router (t : t) (sw : Eio.Std.Switch.t)
    (ensname : ensname) (dweb_api_uri: Uri.t) (force: bool) : artifact option =
      let internal () : artifact option =
        let table = get_table_from_ensname t ensname in
        let payload = Hashtbl.find_opt table "router" in
        match payload with
        | Some x -> Some x
        | None -> (
            log_info (Printf.sprintf "%s: router not found in cache\n" ensname);
            match WPD.get_artifacts_as_bytes_base64 (module CT) sw dweb_api_uri ensname with
            | Some x ->
                let manifest = Extism.Manifest.create [Extism.Manifest.Wasm.data x] in
                let plugin = (Extism.Plugin.of_manifest_exn ~wasi:true manifest) in
                Hashtbl.replace table "router" plugin;
                Some plugin
            | None -> None)
        
        in if force then
          let table = get_table_from_ensname t ensname in
          let _ = hashtable_remove_all_by_key table "router" in
          internal ()
        else internal ()

end
