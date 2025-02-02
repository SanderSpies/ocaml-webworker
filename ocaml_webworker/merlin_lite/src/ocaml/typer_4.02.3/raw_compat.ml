(* {{{ COPYING *(

  This file is part of Merlin, an helper for ocaml editors

  Copyright (C) 2013 - 2015  Frédéric Bour  <frederic.bour(_)lakaban.net>
                             Thomas Refis  <refis.thomas(_)gmail.com>
                             Simon Castellan  <simon.castellan(_)iuwt.fr>

  Permission is hereby granted, free of charge, to any person obtaining a
  copy of this software and associated documentation files (the "Software"),
  to deal in the Software without restriction, including without limitation the
  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
  sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  The Software is provided "as is", without warranty of any kind, express or
  implied, including but not limited to the warranties of merchantability,
  fitness for a particular purpose and noninfringement. In no event shall
  the authors or copyright holders be liable for any claim, damages or other
  liability, whether in an action of contract, tort or otherwise, arising
  from, out of or in connection with the software or the use or other dealings
  in the Software.

)* }}} *)

open Std
open Misc

(* For Fake, Browse, Completion, ... *)

let no_label = ""

(* For Extend *)

let extract_const_string = function
  | {Parsetree. pexp_desc =
       Parsetree.Pexp_constant (Asttypes.Const_string (str, _)) } ->
    Some str
  | _ -> None

(* For Browse_misc *)

let signature_of_summary =
  let open Env in
  let open Types in
  function
  | Env_value (_,i,v)      -> Some (Sig_value (i,v))
  (* Trec_not == bluff, FIXME *)
  | Env_type (_,i,t)       -> Some (Sig_type (i,t,Trec_not))
  (* Texp_first == bluff, FIXME *)
  | Env_extension (_,i,e)  ->
    begin match e.ext_type_path with
    | Path.Pident id when Ident.name id = "exn" ->
      Some (Sig_typext (i,e, Text_exception))
    | _ ->
      Some (Sig_typext (i,e, Text_first))
    end
  | Env_module (_,i,m)     -> Some (Sig_module (i,m,Trec_not))
  | Env_modtype (_,i,m)    -> Some (Sig_modtype (i,m))
  | Env_class (_,i,c)      -> Some (Sig_class (i,c,Trec_not))
  | Env_cltype (_,i,c)     -> Some (Sig_class_type (i,c,Trec_not))
  | Env_open _ | Env_empty | Env_functor_arg _ -> None

let summary_prev = function
  | Env.Env_empty -> None
  | Env.Env_open (s,_)        | Env.Env_value (s,_,_)
  | Env.Env_type (s,_,_)      | Env.Env_extension (s,_,_)
  | Env.Env_module (s,_,_)    | Env.Env_modtype (s,_,_)
  | Env.Env_class (s,_,_)     | Env.Env_cltype (s,_,_)
  | Env.Env_functor_arg (s,_)  ->
    Some s

(* For Type_utils *)

let dest_tstr_eval str =
  match str.Typedtree.str_items with
  | [ { Typedtree.str_desc = Typedtree.Tstr_eval (exp,_) }] -> exp
  | _ -> failwith "unhandled expression"

(* For Completion *)

let fold_types f id env acc =
  Env.fold_types (fun s p (decl,descr) acc -> f s p decl acc) id env acc

let fold_constructors f id env acc =
  Env.fold_constructors
    (fun constr acc -> f constr.Types.cstr_name constr acc)
    id env acc

let labels_of_application =
  let open Typedtree in
  let real_labels_of_application env prefix f args =
    let rec labels t =
      let t = Ctype.repr t in
      match t.Types.desc with
      | Types.Tarrow (label, lhs, rhs, _) ->
        (label, lhs) :: labels rhs
      | _ ->
        let t' = Ctype.full_expand env t in
        if Types.TypeOps.equal t t' then
          []
        else
          labels t'
    in
    let labels = labels f.exp_type in
    let is_application_of label (label',expr,_) =
      match expr with
      | Some {exp_loc = {Location. loc_ghost; loc_start; loc_end}} ->
        label = label'
        && label <> prefix
        && not loc_ghost
        && not (loc_start = loc_end)
      | None -> false
    in
    let unapplied_label (label,_) =
      label <> "" && not (List.exists (is_application_of label) args)
    in
    List.map (List.filter labels ~f:unapplied_label) ~f:(fun (label, ty) ->
        if label.[0] <> '?' then
          "~" ^ label, ty
        else
          match (Ctype.repr ty).Types.desc with
          | Types.Tconstr (path, [ty], _) when Path.same path Predef.path_option ->
            label, ty
          | _ -> label, ty
      )
  in
  fun ~prefix node ->
    let prefix =
      if prefix <> "" && prefix.[0] = '~' then
        String.sub prefix ~pos:1 ~len:(String.length prefix - 1)
      else
        prefix
    in
    match node.exp_desc with
    | Texp_apply (f, args) ->
      real_labels_of_application node.exp_env prefix f args
    | _ -> []

let texp_function_cases = function
  | Typedtree.Texp_function (_,cs,_) -> cs
  | _ -> assert false

let const_string (s, o) = Asttypes.Const_string (s, o)
