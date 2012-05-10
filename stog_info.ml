(*********************************************************************************)
(*                Stog                                                           *)
(*                                                                               *)
(*    Copyright (C) 2012 Maxence Guesdon. All rights reserved.                   *)
(*                                                                               *)
(*    This program is free software; you can redistribute it and/or modify       *)
(*    it under the terms of the GNU General Public License as                    *)
(*    published by the Free Software Foundation; either version 2 of the         *)
(*    License.                                                                   *)
(*                                                                               *)
(*    This program is distributed in the hope that it will be useful,            *)
(*    but WITHOUT ANY WARRANTY; without even the implied warranty of             *)
(*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *)
(*    GNU Library General Public License for more details.                       *)
(*                                                                               *)
(*    You should have received a copy of the GNU General Public                  *)
(*    License along with this program; if not, write to the Free Software        *)
(*    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA                   *)
(*    02111-1307  USA                                                            *)
(*                                                                               *)
(*    As a special exception, you have permission to link this program           *)
(*    with the OCaml compiler and distribute executables, as long as you         *)
(*    follow the requirements of the GNU GPL in regard to all of the             *)
(*    software in the executable aside from the OCaml compiler.                  *)
(*                                                                               *)
(*    Contact: Maxence.Guesdon@inria.fr                                          *)
(*                                                                               *)
(*********************************************************************************)

(** Computing information from articles. *)

open Stog_types;;

let compute_map f_words f_update stog =
  let f art_id article map =
    let on_word map w =
      let set =
        try Stog_types.Str_map.find w map
        with Not_found -> Stog_types.Art_set.empty
      in
      let set = Stog_types.Art_set.add art_id set in
      Stog_types.Str_map.add w set map
    in
    List.fold_left on_word map (f_words article)
  in
  f_update stog
  (Stog_tmap.fold f stog.stog_articles Stog_types.Str_map.empty)
;;

let compute_topic_map stog =
  compute_map
  (fun a -> a.art_topics)
  (fun stog map -> { stog with stog_arts_by_topic = map })
  stog
;;

let compute_keyword_map stog =
  compute_map
  (fun a -> a.art_keywords)
  (fun stog map -> { stog with stog_arts_by_kw = map })
  stog
;;

let compute_graph_with_dates stog =
  let arts = Stog_types.article_list ~by_date:true stog in
  let g = Stog_types.Graph.create () in
  let rec iter g = function
    [] | [_] -> g
  | (art_id, _) :: (next_id, next) :: q ->
      let g = Stog_types.Graph.add g (art_id, next_id, Stog_types.Date) in
      iter g ((next_id, next) :: q)
  in
  { stog with stog_graph = iter g arts }
;;

let next_by_date f_next stog art_id =
  let next = f_next stog.stog_graph art_id in
  let next = List.filter (function (_,Stog_types.Date) -> true | _ -> false) next in
  match next with
    [] -> None
  | (id,_) :: _ -> Some id

let succ_by_date = next_by_date Stog_types.Graph.succ;;
let pred_by_date = next_by_date Stog_types.Graph.pred;;

let add_words_in_graph stog f edge_data =
  let get_last table word =
    try Some(Stog_types.Str_map.find word table)
    with Not_found -> None
  in
  let roots = Stog_types.Graph.pred_roots stog.stog_graph in
  let add_for_node g table id =
    let words = f id in
    let g =
      List.fold_left
      (fun g word ->
         match get_last table word with
           None -> g
         | Some id0 ->
             Stog_types.Graph.add g (id0, id, (edge_data word))
      )
      g
      words
    in
    let table =
      List.fold_left
        (fun t word ->
          Stog_types.Str_map.add word id t)
      table words
    in
    (g, table)
  in
  let rec f (g, table) id =
     let (g, table) = add_for_node g table id in
     let succs = Stog_types.Graph.succ g id in
    let succs = List.filter
      (fun (_,data) -> data = Date) succs
    in
    let succs = Stog_misc.list_remove_doubles
      (List.map fst succs)
    in
    List.fold_left f (g, table) succs
  in
  let (g, _) = List.fold_left f
    (stog.stog_graph, Stog_types.Str_map.empty)
    roots
  in
  { stog with stog_graph = g }
;;

let add_topics_in_graph stog =
  add_words_in_graph stog
  (fun id ->
     let art = Stog_types.article stog id in
     art.art_topics
  )
;;

let add_keywords_in_graph stog =
  add_words_in_graph stog
  (fun id ->
     let art = Stog_types.article stog id in
     art.art_keywords
  )
;;

let add_refs_in_graph stog =
  let g = ref stog.stog_graph in
  let f_ref id env args body =
      match Xtmpl.get_arg args "id" with
      None ->
        []
    | Some hid ->
        prerr_endline (Printf.sprintf "f_ref hid=%s" hid);
        (
         let (id2, _) = Stog_types.article_by_human_id stog hid in
         g := Stog_types.Graph.add !g (id, id2, Stog_types.Ref)
        );
        []
  in
  let f_art id art =
    let funs = [ "ref", f_ref id ] in
    let art = Stog_types.article stog id in
    let env = Xtmpl.env_of_list funs in
    ignore(Xtmpl.apply env art.art_body)
  in
  Stog_tmap.iter f_art stog.stog_articles;
  { stog with stog_graph = !g }
;;

let compute_archives stog =
  let f_mon art_id m mmap =
    let set =
      try Stog_types.Int_map.find m mmap
      with Not_found -> Stog_types.Art_set.empty
    in
    let set = Stog_types.Art_set.add art_id set in
    Stog_types.Int_map.add m set mmap
  in
  let f_art art_id article ymap =
    let {year; month; day = _} = article.art_date in
    let mmap =
      try Stog_types.Int_map.find year ymap
      with Not_found -> Stog_types.Int_map.empty
    in
    let mmap = f_mon art_id month mmap in
    Stog_types.Int_map.add year mmap ymap
  in
  let arch = Stog_tmap.fold f_art
    stog.stog_articles Stog_types.Int_map.empty
  in
  { stog with stog_archives = arch }
;;

let color_of_text s =
  let len = String.length s in
  let r = ref 0 in
  for i = 0 to len - 1 do
    r := !r + Char.code s.[i]
  done;
  let g = ref 0 in
  for i = 0 to len - 1 do
    g := !g + (abs (lnot (Char.code s.[i])))
  done;
  let b = ref 0 in
  for i = 0 to len - 1 do
    b := !b + ((Char.code s.[i]) lsl 2)
  done;
  let (br, bg, bb) =
    if len <= 2 then
      (true, true, true)
    else
      ((Char.code s.[0]) land 5 > 0,
       (Char.code s.[1]) land 5 > 0,
       (Char.code s.[2]) land 5 > 0)
  in
  ((if br then 20 + !r mod 180 else 0),
   (if bg then 20 + !g mod 180 else 0),
   (if bb then 20 + !b mod 180 else 0))
;;

let dot_of_graph f_href stog =
  let g =
    Stog_types.Graph.fold_succ
    stog.stog_graph
    (fun id succs g ->
       List.fold_left
       (fun g (id2, edge) ->
          match edge with
            Date -> g
          | d -> Stog_types.Graph.add g (id, id2, d)
       )
       g succs
    )
    (Stog_types.Graph.create ())
  in
  let f_edge = function
    Date -> assert false
  | Topic word | Keyword word ->
      let (r,g,b) = color_of_text word in
      let col = Printf.sprintf "#%02x%02x%02x" r g b in
      (word, ["fontcolor", col ; "color", col])
  | Ref ->
      ("", ["style", "dashed"])
  in
  let f_node id =
    let art = Stog_types.article stog id in
    let col =
      match art.art_topics with
        [] -> "black"
      | w :: _ ->
          let (r,g,b) = color_of_text w in
          Printf.sprintf "#%02x%02x%02x" r g b
    in
    let href = f_href art in
    (Printf.sprintf "id%d" (Stog_tmap.int id),
     art.art_title,
     ["shape", "rect"; "color", col; "fontcolor", col; "href", href])
  in
  Stog_types.Graph.dot_of_graph ~f_edge ~f_node g
;;

let compute stog =
  let stog = compute_keyword_map stog in
  let stog = compute_topic_map stog in
  let stog = compute_graph_with_dates stog in
  let stog = add_topics_in_graph stog (fun w -> Stog_types.Topic w) in
  let stog = add_keywords_in_graph stog (fun w -> Stog_types.Keyword w) in
  let stog = add_refs_in_graph stog in
  let stog = compute_archives stog in
  stog
;;

let remove_not_published stog =
  let (arts, removed) = Stog_tmap.fold
    (fun id art (acc, removed) ->
       if art.art_published then
         (acc, removed)
       else
         (Stog_tmap.remove acc id, art.art_human_id :: removed)
    )
   stog.stog_articles
   (stog.stog_articles, [])
  in
  let by_hid = List.fold_left
    (fun acc k -> Stog_types.Str_map.remove k acc)
    stog.stog_art_by_human_id removed
  in
  { stog with
    stog_articles = arts ;
    stog_art_by_human_id = by_hid ;
  }
;;
  