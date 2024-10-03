type headers = (string * string) list

module type HttpClient = sig
  type t
  val get : t -> ?headers:headers -> Eio.Std.Switch.t -> Uri.t -> (Cohttp.Response.t * string)
  val create : unit -> t
end

let make_cohttpeioclient net : (module HttpClient) = 
  let https =
    let authenticator =
      match Ca_certs.authenticator () with
      | Ok x -> x
      | Error msg -> (
          match msg with
          | `Msg x ->
              failwith (Format.asprintf "Failed to load CA certificates: %s" x))
    in
    let tls_config = match Tls.Config.client ~authenticator () with
    | Ok config -> config
    | Error (`Msg msg) -> failwith msg
    in
    fun uri raw ->
      let host =
        Uri.host uri
        |> Option.map (fun x -> Domain_name.(host_exn (of_string_exn x)))
      in
      Tls_eio.client_of_flow ?host tls_config raw
    in
    let module CohttpEioClient : HttpClient = struct
      type t = Cohttp_eio.Client.t
    
      let get (t : t) ?(headers=[]) (sw: Eio.Std.Switch.t) uri = 
        let headers = Cohttp.Header.add_list (Cohttp.Header.init ()) headers in
        let resp, body = Cohttp_eio.Client.get ~headers t ~sw uri in 
        (resp, (Eio.Flow.read_all body))

      let create () = Cohttp_eio.Client.make ~https:(Some https) net
    end in
    (module CohttpEioClient : HttpClient)