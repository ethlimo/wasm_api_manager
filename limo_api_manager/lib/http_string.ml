open Http_types
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

let remove_bad_headers ?(bad_header_log_function = None) headers =
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