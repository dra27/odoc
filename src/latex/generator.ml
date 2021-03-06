open Odoc_document.Types

module Doctree = Odoc_document.Doctree

let rec list_concat_map ?sep ~f = function
  | [] -> []
  | [x] -> f x
  | x :: xs ->
    let hd = f x in
    let tl = list_concat_map ?sep ~f xs in
    match sep with
    | None -> hd @ tl
    | Some sep -> hd @ sep :: tl


type break_hierarchy =
  | Aesthetic
  | Simple
  | Line
  | Paragraph
  | Separation


type row_size =
  | Empty
  | Small (** text only *)
  | Large (** No table *)
  | Huge (** tables **)

type elt =
  | Txt of string list
  | Section of section
  | Verbatim of string
  | Internal_ref of reference
  | External_ref of string * t option
  | Label of string
  | Raw of string
  | Tag of string * t
  | Style of [`Emphasis|`Bold|`Superscript|`Subscript|`Italic] * t
  | Code_block of t
  | Inlined_code of t
  | Code_fragment of t
  | Break of break_hierarchy
  | List of list_info
  | Description of (t * t) list
  | Subpage of t
  | Table of table
  | Ligaturable of string

and section = {level:int; label:string option; content:t }
and list_info = { typ : Block.list_type; items: t list }
and table = { row_size: row_size; tbl: t list list}


and t = elt list
and reference = { short:bool; target:string; text: t option }
let const s ppf = Fmt.pf ppf s


let option ppf pp = Fmt.pf ppf "[%t]" pp
let macro name ?(options=[]) pp ppf content =
  Fmt.pf ppf {|\%s%a{%a}|} name
    (Fmt.list option) options
    pp content

let escape_text ~code_hyphenation  =
  let b = Buffer.create 17 in
  fun s ->
    for i = 0 to String.length s - 1 do
      match s.[i] with
      | '{' -> Buffer.add_string b "\\{"
      | '}' ->  Buffer.add_string b "\\}"
      | '\\' ->  Buffer.add_string b "\\textbackslash{}"
      | '%' ->  Buffer.add_string b "\\%"
      | '~' ->  Buffer.add_string b "\\textasciitilde{}"
      | '^' -> Buffer.add_string b "\\textasciicircum{}"
      | '_' ->
        if code_hyphenation then Buffer.add_string b {|\_\allowbreak{}|}
        else Buffer.add_string b {|\_|}
      | '.' when code_hyphenation ->  Buffer.add_string b {|.\allowbreak{}|}
      | ';' when code_hyphenation ->  Buffer.add_string b {|;\allowbreak{}|}
      | ',' when code_hyphenation ->  Buffer.add_string b {|,\allowbreak{}|}

      | '&' ->  Buffer.add_string b "\\&"
      | '#' ->  Buffer.add_string b "\\#"
      | '$' ->  Buffer.add_string b "\\$"


      | c ->  Buffer.add_char b c
    done;
    let s = Buffer.contents b in
    Buffer.reset b;
    s

let escape_ref ppf s =
  for i = 0 to String.length s - 1 do
    match s.[i] with
    | '~' -> Fmt.pf ppf "+t+"
    | '_' -> Fmt.pf  ppf "+u+"
    | '+' -> Fmt.pf ppf "+++"
    | c -> Fmt.pf ppf "%c" c
  done

module Link = struct

  let rec flatten_path ppf (x: Odoc_document.Url.Path.t) = match x.parent with
    | Some p -> Fmt.pf ppf "%a-%s-%s" flatten_path p x.kind x.name
    | None -> Fmt.pf ppf "%s-%s" x.kind x.name

 let page p =
   Format.asprintf "%a" flatten_path p


 let label (x:Odoc_document.Url.t) =
   match x.anchor with
   | "" -> page x.page
   | anchor ->
       Format.asprintf "%a-%s"
       flatten_path x.page
       anchor

  let rec is_class_or_module_path (url : Odoc_document.Url.Path.t) = match url.kind with
    | "module" | "package" | "class" ->
      begin match url.parent with
      | None -> true
      | Some url -> is_class_or_module_path url
      end
    | _ -> false

  let should_inline status url = match status with
    | `Inline | `Open -> true
    | `Closed -> false
    | `Default -> not @@ is_class_or_module_path url


end



let bind pp x ppf = pp ppf x
let mlabel ppf = macro "label" escape_ref ppf
let verbatim = macro "verbatim" Fmt.string
let mbegin ?options = macro "begin" ?options Fmt.string
let mend = macro "end" Fmt.string
let mhyperref pp r ppf =
  match r.target, r.text with
  | "", None -> ()
  | "", Some content ->  pp ppf content
  | s, None ->
    macro "ref" escape_ref ppf s
  | s, Some content ->
      let pp =
        if r.short then pp else
          fun ppf x -> Fmt.pf ppf "%a[p%a]" pp x (macro "pageref*" escape_ref) s in
      macro "hyperref" ~options:[bind escape_ref s] pp ppf content

let label = function
  | None -> []
  | Some  x (* {Odoc_document.Url.Anchor.anchor ; page;  _ }*) -> [Label (Link.label  x)]



let mstyle = function
  | `Emphasis | `Italic -> macro "emph"
  | `Bold -> macro "textbf"
  | `Subscript -> macro "textsubscript"
  | `Superscript -> macro "textsuperscript"



let break ppf level =
  let pre: _ format6 = match level with
    | Aesthetic -> "%%"
    | Line -> {|\\|}
    | Separation -> {|\medbreak|}
    | _ -> "" in
  let post: _ format6 = match level with
    | Line | Separation | Aesthetic | Simple -> ""
    | Paragraph -> "@," in
  Fmt.pf ppf (pre ^^ "@," ^^ post)

let env name pp ?(with_break=false) ?(opts=[]) ?(args=[]) ppf content =
  mbegin ppf name;
  List.iter (Fmt.pf ppf "[%t]") opts;
  List.iter (Fmt.pf ppf "{%t}") args;
  pp ppf content;
  mend ppf name;
  break ppf (if with_break then Simple else Aesthetic)

let inline_code = macro "inlinecode"
let code_block pp ppf x =
  let name = "ocamlcodeblock" in
  mbegin ppf name;
  Fmt.cut ppf ();
  pp ppf x;
  Fmt.cut ppf ();
  mend ppf name

let code_fragment = macro "codefragment"
let sub pp ppf x = env "adjustwidth" ~args:[const "2em"; const "0pt"] pp ppf x


let level_macro = function
  | 0 ->  macro "section"
  | 1 -> macro "subsection"
  | 2 -> macro "subsubsection"
  | 3 | _ -> macro "paragraph"

let none _ppf () = ()

let list kind pp ppf x =
  let list =
    match kind with
    | Block.Ordered -> env "enumerate"
    | Unordered -> env "itemize" in
  let elt ppf = macro "item" pp ppf in
  list
    (Fmt.list ~sep:(fun ppf () -> break ppf Aesthetic) elt)
    ppf
    x

let description pp ppf x =
  let elt ppf (d,elt) = macro "item" ~options:[bind pp d] pp ppf elt in
  let all ppf x =
    Fmt.pf ppf
      {|\kern-\topsep
\makeatletter\advance\%@topsepadd-\topsep\makeatother%% topsep is hardcoded
|};
    Fmt.list ~sep:(fun ppf () -> break ppf Aesthetic) elt ppf x in
  env "description" all ppf x


let escape_entity  = function
  | "#45" -> "-"
  | "gt" -> ">"
  | "#8288" -> ""
  | s -> s


let filter_map f x =
  List.rev @@ List.fold_left (fun acc x ->
    match f x with
    | Some x -> x :: acc
    | None -> acc)
    [] x

let elt_size (x:elt) = match x with
  | Txt _ | Internal_ref _ | External_ref _ | Label _ | Style _ | Inlined_code _ | Code_fragment _ | Tag _ | Break _ | Ligaturable _ -> Small
  | List _ | Section _ | Verbatim _ | Raw _ | Code_block _ | Subpage _ | Description _-> Large
  | Table _  -> Huge

let table = function
  | [] -> []
  | a :: _ as m ->
    let start = List.map (fun _ -> Empty) a in
    let content_size l = List.fold_left (fun s x -> max s (elt_size x)) Empty l in
    let row mask l = List.map2 (fun x y -> max x @@ content_size y) mask l in
    let mask = List.fold_left row start m in
    let filter_empty = function Empty, _ -> None | (Small | Large | Huge), x -> Some x in
    let filter_row row = filter_map filter_empty @@ List.combine mask row in
    let row_size = List.fold_left max Empty mask in
    [Table { row_size; tbl= List.map filter_row m }]

let txt ~verbatim ~in_source ws =
  if verbatim then [Txt ws] else
    let escaped = List.map (escape_text ~code_hyphenation:in_source) ws in
    match List.filter ( (<>) "" ) escaped with
    | [] -> []
    | l -> [ Txt l ]

let entity ~in_source ~verbatim x =
  if in_source && not verbatim then
    Ligaturable (escape_entity x)
  else
    Txt [escape_entity x]

let rec pp_elt ppf = function
  | Txt words ->
    Fmt.list Fmt.string ~sep:none ppf words
  | Section {level; label; content } ->
    let with_label ppf (label,content) =
      pp ppf content;
      match label with
      | None -> ()
      | Some label -> mlabel ppf label in
    level_macro level with_label ppf (label,content)
  | Break lvl -> break ppf lvl
  | Raw s -> Fmt.string ppf s
  | Tag (x,t) -> env ~with_break:true x pp ppf t
  | Verbatim s -> verbatim ppf s
  | Internal_ref r -> hyperref ppf r
  | External_ref (l,x) -> href ppf (l,x)
  | Style (s,x) -> mstyle s pp ppf x
  | Code_block [] -> ()
  | Code_block x -> code_block pp ppf x
  | Inlined_code x -> inline_code pp ppf x
  | Code_fragment x -> code_fragment pp ppf x
  | List {typ; items} -> list typ pp ppf items
  | Description items -> description pp ppf items
  | Table { row_size=Large|Huge as size; tbl } -> large_table size ppf tbl
  | Table { row_size=Small|Empty; tbl } -> small_table ppf tbl
  | Label x -> mlabel ppf x
  | Subpage x ->  sub pp ppf x
  | Ligaturable s -> Fmt.string ppf s

and pp ppf = function
  | [] -> ()
  | Break _ :: (Table _ :: _ as q) -> pp ppf q
  | Table _ as t :: Break _ :: q ->
    pp ppf ( t :: q )
  | Break a :: (Break b :: q) ->
    pp ppf ( Break (max a b) :: q)
  | Ligaturable "-" :: Ligaturable ">" :: q ->
     Fmt.string ppf {|$\rightarrow$|}; pp ppf q
  | a :: q ->
    pp_elt ppf a; pp ppf q

and hyperref ppf r = mhyperref pp r ppf

and href ppf (l,txt) =
  let url ppf s = macro "url" Fmt.string ppf (escape_text ~code_hyphenation:false s) in
  let footnote = macro "footnote" url in
  match txt with
  | Some txt ->
    Fmt.pf ppf {|\href{%s}{%a}%a|} l pp txt footnote l
  | None ->  url ppf l

and large_table size ppf tbl =
    let rec row ppf = function
      | [] -> break ppf Line
      | [a] -> pp ppf a
      | a :: (_ :: _ as q) ->
        Fmt.pf ppf "%a%a%a"
          pp a
          break Aesthetic
          (sub row) q  in
    let matrix ppf m =

      List.iter (row ppf) m in
    match size with
    | Huge -> break ppf Line; matrix ppf tbl
    | Large | _ -> sub matrix ppf tbl

and small_table ppf tbl =
    let columns = List.length (List.hd tbl) in
    let row ppf x =
      let ampersand ppf () = Fmt.pf ppf "& " in
      Fmt.list ~sep:ampersand pp ppf x;
      break ppf Line in
    let matrix ppf m = List.iter (row ppf) m in
    let rec repeat n s ppf = if n = 0 then () else
        Fmt.pf ppf "%c%t" s (repeat (n - 1) s) in
    let table ppf tbl = env "longtable"
      ~opts:[const "l"]
      ~args:[ repeat columns 'l' ]
      matrix ppf tbl in
    Fmt.pf ppf {|{\setlength{\LTpre}{0pt}\setlength{\LTpost}{0pt}%a}|}
    table tbl

let raw_markup (t:Raw_markup.t) =
  match t with
  | `Latex, c -> [Raw c]
  | _ -> []

let source k (t : Source.t) =
  let rec token (x : Source.token) = match x with
    | Elt i -> k i
    | Tag (None, l) -> tokens l
    | Tag (Some s, l) -> [Tag(s, tokens l)]
  and tokens t = list_concat_map t ~f:token in
  tokens t


let rec internalref ~verbatim ~in_source (t : InternalLink.t) =
  match t with
  | Resolved (uri, content) ->
    let target = Link.label uri in
    let text = Some (inline ~verbatim ~in_source content) in
    let short = in_source in
    Internal_ref { short; text; target }
  | Unresolved content ->
    let target = "xref-unresolved" in
    let text = Some (inline ~verbatim ~in_source content) in
    let short = in_source in
    Internal_ref { short; target; text }

and inline ~in_source ~verbatim (l : Inline.t) =
  let one (t : Inline.one) =
    match t.desc with
    | Text _s -> assert false
    | Linebreak -> [Break Line]
    | Styled (style, c) ->
      [Style(style, inline ~verbatim ~in_source c)]
    | Link (ext, c) ->
      let content = inline ~verbatim:false ~in_source:false  c in
      [External_ref(ext, Some content)]
    | InternalLink c ->
      [internalref ~in_source ~verbatim c]
    | Source c ->
      [Inlined_code (source (inline ~verbatim:false ~in_source:true) c)]
    | Raw_markup r -> raw_markup r
    | Entity s -> [entity ~in_source ~verbatim s] in

  let take_text (l: Inline.t) =
    Doctree.Take.until l ~classify:(function
      | { Inline.desc = Text code; _ } -> Accum [code]
      | { desc = Entity e; _ } -> Accum [escape_entity e]
      | _ -> Stop_and_keep
    )
  in
(* if in_source then block_code_txt s else if_not_empty (fun x -> Txt x) s *)
  let rec prettify = function
    | { Inline.desc = Inline.Text _; _ } :: _ as l ->
      let words, _, rest = take_text l in
      txt ~in_source ~verbatim words
      @ prettify rest
    | o :: q -> one o @ prettify q
    | [] -> [] in
  prettify l

let heading (h : Heading.t) =
  let content = inline ~in_source:false ~verbatim:false h.title in
  [Section { label=h.label; level=h.level; content }; Break Aesthetic]

let non_empty_block_code  c =
  let s = source (inline ~verbatim:true ~in_source:true) c in
  match s with
  | [] -> []
  | _ :: _ as l -> [Break Separation; Code_block l; Break Separation]


let non_empty_code_fragment c =
  let s = source (inline ~verbatim:false ~in_source:true) c in
  match s with
  | [] -> []
  | _ :: _ as l -> [Code_fragment l]

let rec block ~in_source (l: Block.t)  =
  let one (t : Block.one) =
    match t.desc with
    | Inline i ->
      inline ~verbatim:false ~in_source:false i
    | Paragraph i ->
      inline ~in_source:false ~verbatim:false i @ if in_source then [] else [Break Paragraph]
    | List (typ, l) ->
      [List { typ; items = List.map (block ~in_source:false) l }]
    | Description l ->
      [Description (List.map (fun (i,b) ->
          inline ~in_source ~verbatim:false i,
          block ~in_source b
      ) l)]
    | Raw_markup r ->
       raw_markup r
    | Verbatim s -> [Verbatim s]
    | Source c -> non_empty_block_code c
  in
  list_concat_map l ~f:one


let rec is_only_text l =
  let is_text : Item.t -> _ = function
    | Heading _ | Text _ -> true
    | Declaration _
      -> false
    |  Include { content = items; _ }
      -> is_only_text items.content
  in
  List.for_all is_text l


let rec documentedSrc (t : DocumentedSrc.t) =
  let open DocumentedSrc in
  let rec to_latex t = match t with
    | [] -> []
    | Code _ :: _ ->
      let take_code l =
        Doctree.Take.until l ~classify:(function
          | Code code -> Accum code
          | _ -> Stop_and_keep
        )
      in
      let code, _, rest = take_code t in
      non_empty_code_fragment code
      @ to_latex rest
    | Alternative (Expansion e) :: rest ->
      begin if Link.should_inline e.status e.url then
        to_latex e.expansion
      else
        non_empty_code_fragment e.summary
    end
        @ to_latex rest
    | Subpage subp :: rest ->
      Subpage (items subp.content.items)
      :: to_latex rest
    | (Documented _ | Nested _) :: _ ->
      let take_descr l =
        Doctree.Take.until l ~classify:(function
          | Documented { attrs; anchor; code; doc }  ->
            Accum [{DocumentedSrc. attrs ; anchor ; code = `D code; doc }]
          | Nested { attrs; anchor; code; doc } ->
            Accum [{DocumentedSrc. attrs ; anchor ; code = `N code; doc }]
          | _ -> Stop_and_keep
        )
      in
      let l, _, rest = take_descr t in
      let one dsrc =
        let content = match dsrc.code with
          | `D code -> inline ~verbatim:false ~in_source:true code
          | `N n -> to_latex n
        in
        let doc = [block ~in_source:true dsrc.doc] in
        (content @ label dsrc.anchor ) :: doc
      in
      table (List.map one l) @ to_latex rest
  in
  to_latex t


and items l =
  let[@tailrec] rec walk_items
      ~only_text acc (t : Item.t list) =
    let continue_with rest elts =
      walk_items ~only_text (List.rev_append elts acc) rest
    in
    match t with
    | [] -> List.rev acc
    | Text _ :: _ as t ->
      let text, _, rest = Doctree.Take.until t ~classify:(function
        | Item.Text text -> Accum text
        | _ -> Stop_and_keep)
      in
      let content = block ~in_source:false text in
      let elts = content in
      elts
      |> continue_with rest
    | Heading h :: rest ->
      heading h
      |> continue_with rest
    | Include
        { kind=_; anchor; doc ; content = { summary; status=_; content } }
      :: rest ->
      let included = items content  in
      let docs = block ~in_source:true  doc in
      let summary = source (inline ~verbatim:false ~in_source:true) summary in
      let content = included in
      (label anchor @ docs @ summary @ content)
      |> continue_with rest

    | Declaration {Item. kind=_; anchor ; content ; doc} :: rest ->
      let content =  label anchor @ documentedSrc content in
      let elts = match doc with
        | [] -> content @ [Break Line]
        | docs -> content @ Break Line :: block ~in_source:true docs @ [Break Separation]
      in
      continue_with rest elts

  and items l = walk_items ~only_text:(is_only_text l) [] l in
  items l


module Doc = struct

let make url filename content children =
  let label = Label (Link.page url) in
  let content = match content with
    | [] -> [label]
    | Section _ as s  :: q -> s :: label :: q
    | q -> label :: q in
  let content ppf = Fmt.pf ppf "@[<v>%a@]@." pp content in
  {Odoc_document.Renderer. filename; content; children }
end

module Page = struct



  let on_sub = function
    | `Page _ -> Some 1
    | `Include _ -> None


  let rec subpage (p:Subpage.t) = if Link.should_inline p.status p.content.url then [] else [ page p.content ]

  and subpages i =
    List.flatten @@ List.map subpage @@ Doctree.Subpages.compute i

  and page ({Page. title; header; items = i; url } as p) =
    let i = Doctree.Shift.compute ~on_sub i in
    let subpages = subpages p in
    let header = items header in
    let content = items i in
    let page =
      Doc.make url title (header@content) subpages
    in
    page

end

let render page = Page.page page
