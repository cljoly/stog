
let output_dir = ref "stog-output";;

let options = [
    "-d", Arg.Set_string output_dir,
    "<dir> set output directory instead of "^ !output_dir ;

  ];;

let usage = Printf.sprintf
  "Usage: %s [options] directory\nwhere options are:"
  Sys.argv.(0)
;;

let main () =
  let remain = ref [] in
  Arg.parse options (fun s -> remain := s :: !remain) usage ;
  match List.rev !remain with
    [] -> failwith usage
  | dirs ->
      let stogs = List.map Stog_io.read_stog dirs in
      let stog = Stog_types.merge_stogs stogs in
      let stog = Stog_info.compute stog in
      Stog_html.generate !output_dir stog
;;

Stog_misc.safe_main main;;