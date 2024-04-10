open Z
open Extism

let wasm = Manifest.Wasm.url "https://github.com/extism/plugins/releases/latest/download/count_vowels.wasm"
let manifest = Manifest.create [wasm]
let plugin = Plugin.of_manifest_exn manifest

let () =
          let result = ProofMain.add_two_things (Z.of_int 3) (Z.of_int 5) in
          Printf.printf "Result: %s\n" (Z.to_string result);;

let () = 
        let result = Plugin.call_string_exn plugin ~name:"count_vowels" "Hello, world!" in
        Printf.printf "Wasm result: %s\n" result;;

