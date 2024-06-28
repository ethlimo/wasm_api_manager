open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type dweb_api_response = {
  x_content_location: string [@key "X-Content-Location"];
  x_content_path: string [@key "X-Content-Path"];
}
[@@deriving yojson]
[@@yojson.allow_extra_fields]