open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type http_query = {
  key : string;
  value : string list;
}
[@@deriving yojson]

let http_query_of_uri_query = function (key, value) -> { key ; value }

type http_request = {
  url : string;
  path: string;
  query: http_query list;
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