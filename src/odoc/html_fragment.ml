open Or_error

let from_mld ~xref_base_uri ~env ~output ~warn_error input =
  Odoc_model.Error.set_warn_error warn_error;
  (* Internal names, they don't have effect on the output. *)
  let page_name = "__fragment_page__" in
  let package = "__fragment_package__" in
  let input_s = Fs.File.to_string input in
  let digest = Digest.file input_s in
  let root =
    let file = Odoc_model.Root.Odoc_file.create_page page_name in
    {Odoc_model.Root.package; file; digest}
  in
  let name = `Page (root, Odoc_model.Names.PageName.of_string page_name) in
  let location =
    let pos =
      Lexing.{
        pos_fname = input_s;
        pos_lnum = 0;
        pos_cnum = 0;
        pos_bol = 0
      }
    in
    Location.{ loc_start = pos; loc_end = pos; loc_ghost = true }
  in
  let to_html content =
    (* This is a mess. *)
    let page = Odoc_model.Lang.Page.{ name; content; digest } in
    let env = Env.build env (`Page page) in
    let resolved =
      Odoc_xref2.Link.resolve_page env page
      |> Odoc_xref2.Lookup_failures.to_warning ~filename:input_s
      |> Odoc_model.Error.shed_warnings
    in

    let page = Odoc_document.Comment.to_ir resolved.content in
    let html = Odoc_html.Generator.doc ~xref_base_uri page in
    let oc = open_out (Fs.File.to_string output) in
    let fmt = Format.formatter_of_out_channel oc in
    Format.fprintf fmt "%a@." (Format.pp_print_list (Tyxml.Html.pp_elt ())) html;
    close_out oc;
    Ok ()
  in
  match Fs.File.read input with
  | Error _ as e -> e
  | Ok str ->
    match Odoc_loader.read_string name location str with
    | Error e -> Error (`Msg (Odoc_model.Error.to_string e))
    | Ok (`Docs content) -> to_html content
    | Ok `Stop -> to_html [] (* TODO: Error? *)
