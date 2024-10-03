type domain_replacement = {suffix: string; replacement: string}
type domain_replacement_list = domain_replacement list

let create_domain_replacement suffix replacement = 
  if String.length suffix = 0 || String.length replacement = 0 then
    None
  else
    Some {suffix; replacement}

let create_domain_replacement_list replacements =
  let rec create_aux acc = function
    | [] -> Some (List.rev acc)
    | (Some suffix, Some replacement)::rest ->
      (match create_domain_replacement suffix replacement with
      | None -> None
      | Some dr -> create_aux (dr::acc) rest)
    | (None, None)::rest -> create_aux acc rest
    | _ -> failwith "Invalid domain replacement"
  in
  create_aux [] replacements

let replace_suffix suffix replacement str =
  let len = String.length str in
  let suffix_len = String.length suffix in
  if len >= suffix_len && String.sub str (len - suffix_len) suffix_len = suffix then
    String.sub str 0 (len - suffix_len) ^ replacement
  else
    str

let replace_domain_suffix domain_replacement_list str =
  let rec replace_aux = function
    | [] -> str
    | dr::rest ->
      let replaced_str = replace_suffix dr.suffix dr.replacement str in
      if replaced_str = str then
        replace_aux rest
      else
        replaced_str
  in
  replace_aux domain_replacement_list


let log_warning str = Logs.warn (fun f -> f "%s" str)
let log_error ex = Logs.err (fun f -> f "%a" Eio.Exn.pp ex)
let log_exn_as_warning ex = Logs.err (fun f -> f "%a" Eio.Exn.pp ex)
let log_info str = Logs.info (fun f -> f "%s" str)