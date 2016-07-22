(*********************************************************************************)
(*                Stog                                                           *)
(*                                                                               *)
(*    Copyright (C) 2012-2015 INRIA All rights reserved.                         *)
(*    Author: Maxence Guesdon, INRIA Saclay                                      *)
(*                                                                               *)
(*    This program is free software; you can redistribute it and/or modify       *)
(*    it under the terms of the GNU General Public License as                    *)
(*    published by the Free Software Foundation, version 3 of the License.       *)
(*                                                                               *)
(*    This program is distributed in the hope that it will be useful,            *)
(*    but WITHOUT ANY WARRANTY; without even the implied warranty of             *)
(*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the               *)
(*    GNU General Public License for more details.                               *)
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

(** *)

open Stog_types;;

module XR = Xtmpl_rewrite
module Xml = Xtmpl_xml

let module_name = "sitemap";;
let rc_file stog = Stog_plug.plugin_config_file stog module_name;;

module W = Ocf.Wrapper
type info =
  {
    in_sitemap : bool [@ocf W.bool, true] ;
    frequency : string option
        [@ocf W.option W.string, None]
        [@ocf.doc "\"\"|always|hourly|daily|weekly|monthly|yearly|never"];
    priority : string option
        [@ocf W.option W.string, None]
        [@ocf.doc "0..1.0"] ;
  } [@@ocf]

type sitemap_data =
    { default_by_type : info Stog_types.Str_map.t
      [@ocf.wrapper W.string_map
        Stog_types.Str_map.fold
          Stog_types.Str_map.add
          Stog_types.Str_map.empty
          info_wrapper] ;
      out_file : string
        [@ocf.wrapper W.string]
        [@ocf.doc "file where to generate the sitemap"];
    } [@@ocf]

let group data =
  let w = sitemap_data_wrapper
    ~default_by_type: data.default_by_type
      ~out_file: data.out_file
  in
  let option_t = Ocf.option w data in
  let g = Ocf.as_group option_t in
  (g, option_t)

let load_config _ (stog,data) _ =
  let (group, t) = group data in
  let rc_file = rc_file stog in
  if not (Sys.file_exists rc_file) then Ocf.to_file group rc_file ;
  try
    Ocf.from_file group rc_file;
    (stog, Ocf.get t)
  with
  | Ocf.Error e -> failwith (Ocf.string_of_error e)
;;

type url_entry = {
    url_loc : Stog_url.t ;
    url_lastmod : Stog_types.date ;
    url_freq : string option ;
    url_prio : string option ;
  }

let gen_sitemap stog data entries =
  let f_entry e =
    XR.(
     node ("","url")
      ((node ("","loc") [cdata (Stog_url.to_string e.url_loc)]) ::
        (node ("","lastmod")
         [cdata (Stog_date.to_string e.url_lastmod)]
        ) ::
          (match e.url_freq with
             None -> []
           | Some s -> [node ("","changefreq") [cdata s]]) @
          (match e.url_prio with
             None -> []
           | Some s -> [node ("","priority") [cdata s]])
       )
    )
  in
  let atts = XR.atts_one ("","xmlns")
    [XR.cdata "http://www.sitemaps.org/schemas/sitemap/0.9"]
  in
  let body = XR.node ("","urlset") ~atts (List.map f_entry entries) in
  let xml = XR.to_string ~xml_atts: false [body] in
  let file = Filename.concat stog.stog_outdir data.out_file in
  Stog_misc.file_of_string ~file xml

let generate =
  let f_doc stog data doc_id doc acc =
    let default =
      try Stog_types.Str_map.find doc.doc_type data.default_by_type
      with Not_found ->
          { in_sitemap = true ;
            frequency = Some "always" ;
            priority = Some "0.5" ;
          }
    in
    match
      match Stog_types.get_def doc.doc_defs ("","in-sitemap") with
        None -> default.in_sitemap
      | Some (_, [XR.D {Xml.text = "false"}]) -> false
      | _ -> true
    with
      false -> acc
    | true ->
        let url_lastmod = Stog_date.now () in
        let url_freq =
          match Stog_types.get_def doc.doc_defs ("","sitemap-frequency") with
          | Some (_, [XR.D s]) -> Stog_misc.opt_of_string s.Xml.text
          | _ -> default.frequency
        in
        let url_prio =
          match Stog_types.get_def doc.doc_defs ("","sitemap-priority") with
          | Some (_, [XR.D s]) -> Stog_misc.opt_of_string s.Xml.text
          | _ -> default.priority
        in
        { url_loc = Stog_engine.doc_url stog doc ;
          url_lastmod ; url_freq ; url_prio ;
        } :: acc
  in
  fun env (stog, data) _docs ->
    let entries = Stog_tmap.fold (f_doc stog data) stog.stog_docs [] in
    gen_sitemap stog data entries ;
    (stog, data)
;;


let level_funs =
  [
    "load-config", Stog_engine.Fun_stog_data load_config ;
    "generate", Stog_engine.Fun_stog_data generate ;
  ]
;;

let default_levels =
  List.fold_left
    (fun map (name, levels) -> Stog_types.Str_map.add name levels map)
    Stog_types.Str_map.empty
    [
      "load-config", [ -2 ] ;
      "generate", [ 1000 ] ;
    ]

let default_data  =
  { out_file = "sitemap.xml" ;
    default_by_type = Stog_types.Str_map.empty ;
  }

let make_module ?levels () =
  let levels = Stog_html.mk_levels module_name level_funs default_levels ?levels () in
  let module M =
  struct
    type data = sitemap_data
    let modul = {
        Stog_engine.mod_name = module_name ;
        mod_levels = levels ;
        mod_data = default_data ;
       }

    type cache_data = unit
    let cache_load _stog data doc t = data
    let cache_store _stog data doc = ()
  end
  in
  (module M : Stog_engine.Module)
;;

let f stog =
  let levels =
    try Some (Stog_types.Str_map.find module_name stog.Stog_types.stog_levels)
    with Not_found -> None
  in
  make_module ?levels ()
;;

let () = Stog_engine.register_module module_name f;;
