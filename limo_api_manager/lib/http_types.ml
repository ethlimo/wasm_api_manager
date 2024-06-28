open Ppx_yojson_conv_lib.Yojson_conv.Primitives

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