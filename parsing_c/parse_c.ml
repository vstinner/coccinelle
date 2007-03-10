open Common open Commonop

module TH = Token_helpers 
module LP = Lexer_parser

(*****************************************************************************)
(* Wrappers *)
(*****************************************************************************)
let pr2 s = 
  if !Flag_parsing_c.verbose_parsing 
  then Common.pr2 s
    
(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let lexbuf_to_strpos lexbuf     = 
  (Lexing.lexeme lexbuf, Lexing.lexeme_start lexbuf)    

let token_to_strpos tok = 
  let (parse_info,_cocci_info) = Token_helpers.info_from_token tok in
  (parse_info.Common.str, parse_info.Common.charpos)


let error_msg_tok file tok = 
  if !Flag_parsing_c.verbose_parsing
  then Common.error_message file (token_to_strpos tok) 
  else ("error in " ^ file ^ "set verbose_parsing for more info")


let print_bad line_error (start_line, end_line) filelines  = 
  begin
    pr2 ("badcount: " ^ i_to_s (end_line - start_line));
    for i = start_line to end_line do 
      if i = line_error 
      then  pr2 ("BAD:!!!!!" ^ " " ^ filelines.(i)) 
      else  pr2 ("bad:" ^ " " ^      filelines.(i)) 
    done
  end



let mk_info_item2 filename toks = 
  let toks' = List.rev toks in
  let buf = Buffer.create 100 in
  let s = 
    (* old: get_slice_file filename (line1, line2) *)
    begin
      toks' +> List.iter (fun tok -> 
        let s = fst (token_to_strpos tok)in
        Buffer.add_string buf s;
      );
      Buffer.contents buf
    end
  in
  (s, toks') 

let mk_info_item a b = 
  Common.profile_code "C parsing.mk_info_item" 
    (fun () -> mk_info_item2 a b)



(*****************************************************************************)
(* Stat *)
(*****************************************************************************)
type parsing_stat = {
    filename: filename;
    mutable have_timeout: bool;

    mutable correct: int;  
    mutable bad: int;

    (* if want to know exactly what was passed through
     * mutable passing_through_lines: int;
     * it differs from bad by starting from the error to
     * the synchro point instead of strating from start of
     * function to end of function.
     *)

  } 

let default_stat file =  { 
    filename = file;
    have_timeout          = false;
    correct = 0; bad = 0;
  }

(* todo: stat per dir ?  give in terms of func_or_decl numbers:   
 * nbfunc_or_decl pbs / nbfunc_or_decl total ?/ 
 *
 * note: cela dit si y'a des fichiers avec des #ifdef dont on connait pas les 
 * valeurs alors on parsera correctement tout le fichier et pourtant y'aura 
 * aucune def  et donc aucune couverture en fait.   
 * ==> TODO evaluer les parties non pars� ? 
 *)

let print_parsing_stat_list = fun statxs -> 
  let total = (List.length statxs) in
  let perfect = 
    statxs 
      +> List.filter (function 
          {have_timeout = false; bad = 0} -> true | _ -> false)
      +> List.length 
  in
  pr2 "\n\n\n---------------------------------------------------------------";
  pr2 "pbs with files:";
  statxs 
    +> List.filter (function 
      | {have_timeout = true} -> true 
      | {bad = n} when n > 0 -> true 
      | _ -> false)
    +> List.iter (function 
        {filename = file; have_timeout = timeout; bad = n} -> 
          pr2 (file ^ "  " ^ (if timeout then "TIMEOUT" else i_to_s n));
        );
  pr2 "\n\n\n---------------------------------------------------------------";
  pr2 (
  (sprintf "NB total files = %d; " total) ^
  (sprintf "perfect = %d; " perfect) ^
  (sprintf "pbs = %d; "     (statxs +> List.filter (function 
      {have_timeout = b; bad = n} when n > 0 -> true | _ -> false) 
                               +> List.length)) ^
  (sprintf "timeout = %d; " (statxs +> List.filter (function 
      {have_timeout = true; bad = n} -> true | _ -> false) 
                               +> List.length)) ^
  (sprintf "=========> %d" ((100 * perfect) / total)) ^ "%"
                                                          
 );
  let good = (statxs +> List.fold_left (fun acc {correct = x} -> acc+x) 0) in
  let bad  = (statxs +> List.fold_left (fun acc {bad = x} -> acc+x) 0)  in
  let gf, badf = float_of_int good, float_of_int bad in
  pr2 (
  (sprintf "nb good = %d,  nb bad = %d    " good bad) ^
  (sprintf "=========> %f"  (100.0 *. (gf /. (gf +. badf))) ^ "%"
   )
  )




(*****************************************************************************)
(* Lexing only *)
(*****************************************************************************)

(* called by parse_print_error_heuristic *)
let tokens2 file = 
 let table     = Common.full_charpos_to_pos file in

 Common.with_open_infile file (fun chan -> 
  let lexbuf = Lexing.from_channel chan in
  try 
    let rec tokens_aux () = 
      let result = Lexer_c.token lexbuf in
      (* add the line x col information *)
      let result = 
        Token_helpers.visitor_info_from_token 
          (fun (parse_info,cocciinfo) -> 
            Common.complete_parse_info file table parse_info,
            cocciinfo
          ) result 
      in
     
      if TH.is_eof result
      then [result]
      else result::(tokens_aux ())
    in
    tokens_aux ()
  with
    | Lexer_c.Lexical s -> 
        failwith ("lexical error " ^ s ^ "\n =" ^ 
                  (Common.error_message file (lexbuf_to_strpos lexbuf)))
    | e -> raise e
 )

let tokens a = 
  Common.profile_code "C parsing.tokens" (fun () -> tokens2 a)


let tokens_string string = 
  let lexbuf = Lexing.from_string string in
  try 
    let rec tokens_s_aux () = 
      let result = Lexer_c.token lexbuf in
      if TH.is_eof result
      then [result]
      else result::(tokens_s_aux ())
    in
    tokens_s_aux ()
  with
    | Lexer_c.Lexical s -> failwith ("lexical error " ^ s ^ "\n =" )
    | e -> raise e


(*****************************************************************************)
(* Parsing, but very basic, no more used *)
(*****************************************************************************)

(*
 * !!!Those function use refs, and are not reentrant !!! so take care.
 * It use globals defined in Lexer_parser.
 *)

let parse file = 
  let lexbuf = Lexing.from_channel (open_in file) in
  let result = Parser_c.main Lexer_c.token lexbuf in
  result


let parse_print_error file = 
  let chan = (open_in file) in
  let lexbuf = Lexing.from_channel chan in

  let error_msg () = Common.error_message file (lexbuf_to_strpos lexbuf) in
  try 
    lexbuf +> Parser_c.main Lexer_c.token
  with 
  | Lexer_c.Lexical s ->   
      failwith ("lexical error " ^s^ "\n =" ^  error_msg ())
  | Parsing.Parse_error -> 
      failwith ("parse error \n = " ^ error_msg ())
  | Semantic_c.Semantic (s, i) -> 
      failwith ("semantic error " ^ s ^ "\n =" ^ error_msg ())
  | e -> raise e




(*****************************************************************************)
(* Parsing subelements, useful to debug parser *)
(*****************************************************************************)

(*
 * !!!Those function use refs, and are not reentrant !!! so take care.
 * It use globals defined in Lexer_parser.
 *)


(* old: 
 * let parse_gen parsefunc s = 
 *   let lexbuf = Lexing.from_string s in
 *   let result = parsefunc Lexer_c.token lexbuf in
 *   result
*)

let parse_gen parsefunc s = 
  let toks = tokens_string s +> List.filter TH.is_not_comment in

  let all_tokens = ref toks in
  let cur_tok    = ref (List.hd !all_tokens) in

  let lexer_function = 
    (fun _ -> 
      if TH.is_eof !cur_tok
      then (pr2 "ALREADY AT END"; !cur_tok)
      else
        let v = Common.pop2 all_tokens in
        cur_tok := v;
        !cur_tok
    ) 
  in
  let lexbuf_fake = Lexing.from_function (fun buf n -> raise Impossible) in
  let result = parsefunc lexer_function lexbuf_fake in
  result


let type_of_string      = parse_gen Parser_c.type_name
let statement_of_string = parse_gen Parser_c.statement
let expression_of_string = parse_gen Parser_c.expr

(* ex: statement_of_string "(struct us_data* )psh->hostdata = NULL;" *)






(*****************************************************************************)
(* Error recovery *)
(*****************************************************************************)

(* todo: do something if find Parser_c.Eof ? *)
let rec find_next_synchro next already_passed =

  (* maybe because not enough }, because for example an ifdef that
   * contains in both branch some opening {, then we later eat too much,
   * "on deborde sur la fonction d'apres", so maybe can find synchro
   * point inside already_passed instead of looking in next. But take
   * care! must go forward, we must not stay in infinite loop! So look
   * at premier(external_declaration2) in parser.output and pass at
   * least this first tokens. 
   * 
   * I have chosen to start search for next synchro point after the 
   * first { I found, so quite sure we will not loop.
   *)

  let last_round = List.rev already_passed in
  let (before, after) = 
    Common.span (fun tok -> 
      match tok with
      | Parser_c.TOBrace _ -> false
      | _ -> true
    ) last_round
  in
  find_next_synchro_orig (after ++ next)  (List.rev before)
    
    

and find_next_synchro_orig next already_passed =

    match next with
    | [] ->  
        pr2 "ERROR-RECOV: end of file while in recovery mode"; 
        already_passed, []

    | (Parser_c.TCBrace i as v)::xs when TH.col_of_tok v = 0 -> 
        pr2 ("ERROR-RECOV: found sync point at line "^i_to_s (TH.line_of_tok v));

        (* perhaps a }; obsolete now, because parser.mly allow empty ';' *)
      (match xs with
      | [] -> raise Impossible (* there is a EOF token normally *)
      | Parser_c.TPtVirg iptvirg::xs -> 
          pr2 "ERROR-RECOV: found sync bis, eating } and ;";
          (Parser_c.TPtVirg iptvirg)::v::already_passed, xs

      | Parser_c.TIdent x::Parser_c.TPtVirg iptvirg::xs -> 
          pr2 "ERROR-RECOV: found sync bis, eating ident, }, and ;";
          (Parser_c.TPtVirg iptvirg)::(Parser_c.TIdent x)::v::already_passed, 
          xs

      | Parser_c.TCommentSpace sp::Parser_c.TIdent x::Parser_c.TPtVirg iptvirg
        ::xs -> 
          pr2 "ERROR-RECOV: found sync bis, eating ident, }, and ;";
          (Parser_c.TCommentSpace sp)::
            (Parser_c.TPtVirg iptvirg)::
            (Parser_c.TIdent x)::
            v::
            already_passed, 
          xs

      | _ -> 
          v::already_passed, xs
      )
  | v::xs when TH.col_of_tok v = 0 && TH.is_start_of_something v  -> 
      pr2 ("ERROR-RECOV: found sync 2 at line "^ i_to_s (TH.line_of_tok v));
      already_passed, v::xs

  | v::xs -> 
      find_next_synchro_orig xs (v::already_passed)

      
(*****************************************************************************)
(* Include/Define hacks *)
(*****************************************************************************)

(* ------------------------------------------------------------------------- *)
(* helpers *)
(* ------------------------------------------------------------------------- *)
let tok_set s (info, annot) =  {info with Common.str = s;}, annot

(* used to generate new token from existing one *)
let new_info posadd str (info, annot) = 
  { info with
    charpos = info.charpos + posadd;
    str     = str;
    column = info.column + posadd;
  }, ref Ast_c.emptyAnnot 
 (*must generate a new ref each time, otherwise share*)


(* adjust token because fresh token coming from a Parse_c.token_string *)
let adjust_tok posadd filename tok = 
  tok +> TH.visitor_info_from_token (fun (info, annot) -> 
    { info with
      charpos = info.charpos + posadd;
      file = filename;
    }, annot
  )
      

(* ------------------------------------------------------------------------- *)
(* parsing #define body *)
(* ------------------------------------------------------------------------- *)

(* todo: if just one token which is a typedef ? have a DefineType ?
 * todo: expression_of_string can do side effect on Lexer_parser and so
 * screwd the rest of the parsing ? *)

let tokens_define_val posadd bodys info = 

    
     if (try let _ = expression_of_string bodys in true with _ -> false) ||
        (try let _ = type_of_string bodys       in true with _ -> false)
     then 

       tokens_string bodys
       +> Common.list_init 
       +> List.map (fun tok -> 
         adjust_tok  
           (posadd + Ast_c.get_pos_of_info info)
           (Ast_c.get_file_of_info info) 
           tok)
       +> List.map (fun tok -> 
         match tok with 
         (* can't use here Lexer_parser, nor our heuristic because on case 
          * such as #define chip_t vortex_t, we have no info on vortex_t yet
          * so have to do inference checking only based on name information.
          * It is quite specific to rule66/ ...
          *)
         | Parser_c.TIdent (s,ii) -> 
             if s =~ ".*_t$" 
             then begin
               pr2 ("TYPEDEF: in #define, promoting:" ^ s);
               Parser_c.TypedefIdent (s, ii)
             end
             else 
               tok
         | _ -> tok
       )
           
       
     else 
       [Parser_c.TDefText (bodys, (new_info posadd bodys info));]


(* ------------------------------------------------------------------------- *)
(* returns a pair (replaced token, list of next tokens) *)
(* ------------------------------------------------------------------------- *)

let tokens_include (info, includes, filename) = 
  Parser_c.TIncludeStart (tok_set includes info), 
  [Parser_c.TIncludeFilename 
      (filename, (new_info (String.length includes) filename info))
  ]


let tokens_define_simple (info, define, ident, bodys) = 

  let tokens_body = 
    tokens_define_val (String.length (define ^ ident)) bodys info 
  in

  Parser_c.TDefVarStart (tok_set define info),
  [Parser_c.TDefIdent (ident, (new_info (String.length define) ident info))]
  ++ tokens_body ++ 
  [Parser_c.TDefEOL
      (new_info (String.length (define ^ ident ^ bodys)) "" info)]



let tokens_define_func (info, define, ident, params, bodys) = 
  (* don't want last EOF, hence the list_init *)

  let tokens_params = 
    tokens_string params
    +> Common.list_init 
    +> List.map (fun tok -> 
      adjust_tok 
        (String.length (define ^ ident) + Ast_c.get_pos_of_info info)
        (Ast_c.get_file_of_info info) 
        tok
    )
  in

  let tokens_body = 
    tokens_define_val (String.length (define ^ ident ^ params)) bodys info 
  in

  Parser_c.TDefFuncStart (tok_set define info),
  [Parser_c.TDefIdent (ident, (new_info (String.length define) ident info))]
  ++ tokens_params
  ++ tokens_body 
  ++
  [Parser_c.TDefEOL
      (new_info (String.length (define ^ ident ^ params ^ bodys)) "" info)]

  
(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

type info_item =  string * Parser_c.token list

type program2 = programElement2 list
     and programElement2 = Ast_c.programElement * info_item


(* note: as now go in 2 pass, there is first all the error message of
 * the lexer, and then the error of the parser. It is no more
 * interwinded.
 * 
 * The use of local refs (remaining_tokens, passed_tokens, ...) makes
 * possible error recovery. Indeed, they allow to skip some tokens and
 * still be able to call again the ocamlyacc parser. It is ugly code
 * because we cant modify ocamllex and ocamlyacc. As we want some
 * extended lexing tricks, we have to use such refs.

 * Those refs are now also used for my lalr(k) technique. Indeed They
 * store the futur and previous tokens that were parsed, and so
 * provide enough context information for powerful lex trick.

 * - passed_tokens_last_ckp stores the passed tokens since last
 *   checkpoint. Used for NotParsedCorrectly and also for build the
 *   info_item attached to each program_element.
 * - passed_tokens is used for lookahead, in fact for lookback.
 * - remaining_tokens_clean is used for lookahead. Now remaining_tokens
 *   contain some comments and so would make pattern matching difficult
 *   in lookahead. Hence this variable. We would like also to get rid 
 *   of cpp instruction because sometimes a cpp instruction is between
 *   two tokens and makes a pattern matching fail. But lookahead also
 *   transform some cpp instruction (in comment) so can't remove them.

 * So remaining_tokens, passed_tokens_last_ckp contain comment-tokens,
 * whereas passed_tokens and remaining_tokens_clean does not contain
 * comment-tokens.

 * Normally we have:
 * toks = (reverse passed_tok) ++ cur_tok ++ remaining_tokens   
 *    after the call to pop2.
 * toks = (reverse passed_tok) ++ remaining_tokens   
 *     at the and of the lexer_function call.
 * At the very beginning, cur_tok and remaining_tokens overlap, but not after.
 * At the end of lexer_function call,  cur_tok  overlap  with passed_tok.
 * 
 * !!!This function use refs, and is not reentrant !!! so take care.
 * It use globals defined in Lexer_parser.
 *)


let parse_print_error_heuristic2 file = 

  (* -------------------------------------------------- *)
  (* call lexer and get all the tokens *)
  (* -------------------------------------------------- *)
  LP.lexer_reset_typedef(); 
  let toks = tokens file in
  let toks = Parsing_hacks.fix_tokens_cpp toks in

  let filelines = (""::Common.cat file) +> Array.of_list in

  let stat = default_stat file in

  let remaining_tokens       = ref toks in
  let remaining_tokens_clean = ref (toks +> List.filter TH.is_not_comment) 
  in
  let cur_tok                = ref (List.hd !remaining_tokens) in
  let passed_tokens_last_ckp = ref [] in 
  let passed_tokens          = ref [] in

  (* hacked_lex *)
  let rec lexer_function = (fun lexbuf -> 

    if TH.is_eof !cur_tok
    then begin pr2 "ALREADY AT END"; !cur_tok end
    else begin
      let v = pop2 remaining_tokens in
      cur_tok := v;

      if !Flag_parsing_c.debug_lexer then pr2 (Dumper.dump v);

      if TH.is_comment v
      then begin
        passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
        lexer_function lexbuf
      end
      else begin
        let x = pop2 remaining_tokens_clean  in
        assert (x = v);

        (match v with
        | Parser_c.TInclude (includes, filename, info) -> 
            if not !LP._lexer_hint.LP.toplevel 
            then begin
              pr2 ("CPP-INCLUDE: inside function, I treat it as comment");
              let v = Parser_c.TCommentCpp info in
              passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
              lexer_function lexbuf
            end
            else begin
              let (v,new_tokens) = tokens_include (info, includes, filename)
              in
              let new_tokens_clean = 
                new_tokens +> List.filter TH.is_not_comment
              in
              passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
              passed_tokens := v::!passed_tokens;
              remaining_tokens := new_tokens ++ !remaining_tokens;
              remaining_tokens_clean := 
                new_tokens_clean ++ !remaining_tokens_clean;
              v
            end
            
        | Parser_c.TDefVar (define, ident, bodys, info) -> 
            if not !LP._lexer_hint.LP.toplevel 
            then begin
              pr2 ("CPP-DEFINE: inside function, I treat it as comment");
              let v = Parser_c.TCommentCpp info in
              passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
              lexer_function lexbuf
            end
            else begin
              let (v,new_tokens) = 
                tokens_define_simple (info, define, ident, bodys)
              in
              let new_tokens_clean = 
                new_tokens +> List.filter TH.is_not_comment
              in
              passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
              passed_tokens := v::!passed_tokens;
              remaining_tokens := new_tokens ++ !remaining_tokens;
              remaining_tokens_clean := 
                new_tokens_clean ++ !remaining_tokens_clean;
              !LP._lexer_hint.LP.define <- true;
              v
            end

        | Parser_c.TDefFunc (define, ident, params, bodys, info) -> 
            if not !LP._lexer_hint.LP.toplevel 
            then begin
              pr2 ("CPP-DEFINE: inside function, I treat it as comment");
              let v = Parser_c.TCommentCpp info in
              passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
              lexer_function lexbuf
            end
            else begin
              let (v,new_tokens) = 
                tokens_define_func (info, define, ident, params, bodys)
              in
              let new_tokens_clean = 
                new_tokens +> List.filter TH.is_not_comment
              in
              passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
              passed_tokens := v::!passed_tokens;
              remaining_tokens := new_tokens ++ !remaining_tokens;
              remaining_tokens_clean := 
                new_tokens_clean ++ !remaining_tokens_clean;
              !LP._lexer_hint.LP.define <- true;
              v
            end
        | _ when !LP._lexer_hint.LP.define -> 
            (* no processing for body of define, otherwise
             * get some parse error with bad typedef inference
             * or even good one that does not lead to an expression
             * anymore whereas with expression_of_string it was 
             * an expression.
             *)
            passed_tokens_last_ckp := v::!passed_tokens_last_ckp;
            passed_tokens := v::!passed_tokens;
            v

        | _ -> 

            (* typedef_fix1 *)
            let v = match v with
              | Parser_c.TIdent (s, ii) -> 
                  if LP.is_typedef s 
                  then Parser_c.TypedefIdent (s, ii)
                  else Parser_c.TIdent (s, ii)
              | x -> x
            in
          
            let v = Parsing_hacks.lookahead 
              (v::!remaining_tokens_clean) !passed_tokens 
            in

            passed_tokens_last_ckp := v::!passed_tokens_last_ckp;

            (* the lookahead may have change the status of the token and
             * consider it as a comment, for instance some #include are
             * turned into comments hence this code. *)
            match v with
            | Parser_c.TCommentCpp _ -> lexer_function lexbuf
            | v -> 
                passed_tokens := v::!passed_tokens;
                v
        )
      end
    end
  )
  in
  let lexbuf_fake = Lexing.from_function (fun buf n -> raise Impossible) in



  let rec loop () =

    if not (LP.is_enable_state()) && !Flag_parsing_c.debug_typedef
    then pr2 "TYPEDEF:_handle_typedef=false. Not normal if dont come from exn";

    (* normally have to do that only when come from an exception in which
     * case the dt() may not have been done 
     * TODO but if was in scoped scope ? have to let only the last scope
     * so need do a LP.lexer_reset_typedef ();
     *)
    LP.enable_typedef();  
    LP._lexer_hint := { (LP.default_hint ()) with LP.toplevel = true; };

    (* todo?: I am not sure that it represents current_line, cos maybe
     * cur_tok partipated in the previous parsing phase, so maybe cur_tok
     * is not the first token of the next parsing phase. Same with checkpoint2.
     * It would be better to record when we have a } or ; in parser.mly,
     *  cos we know that they are the last symbols of external_declaration2.
     *)
    let checkpoint = TH.line_of_tok !cur_tok in

    passed_tokens_last_ckp := [];

    let elem = 
      (try 
          (* -------------------------------------------------- *)
          (* Call parser *)
          (* -------------------------------------------------- *)
          Parser_c.celem lexer_function lexbuf_fake
        with e -> 
          begin
            (match e with
            (* Lexical is no more launched I think *)
            | Lexer_c.Lexical s -> 
                pr2 ("lexical error " ^s^ "\n =" ^ error_msg_tok file !cur_tok)
            | Parsing.Parse_error -> 
                pr2 ("parse error \n = " ^ error_msg_tok file !cur_tok)
            | Semantic_c.Semantic (s, i) -> 
                pr2 ("semantic error " ^s^ "\n ="^ error_msg_tok file !cur_tok)
            | e -> raise e
            );
            let line_error = TH.line_of_tok !cur_tok in

            (*  error recovery, go to next synchro point *)
            let (passed_tokens', remaining_tokens') =
              find_next_synchro !remaining_tokens !passed_tokens_last_ckp
            in
            remaining_tokens := remaining_tokens';
            passed_tokens_last_ckp := passed_tokens';

            cur_tok := List.hd passed_tokens';
            passed_tokens := [];           (* enough ? *)

            (* with error recovery, remaining_tokens and
             * remaining_tokens_clean may not be in sync 
             *)
            remaining_tokens_clean := 
              (!remaining_tokens +> List.filter TH.is_not_comment);

            let checkpoint2 = TH.line_of_tok !cur_tok in
            print_bad line_error (checkpoint, checkpoint2) filelines;

            let info_of_bads = 
              Common.map_eff_rev TH.info_from_token !passed_tokens_last_ckp 
            in 
            Ast_c.NotParsedCorrectly info_of_bads
          end
      ) 
    in

    (* again not sure if checkpoint2 corresponds to end of bad region *)
    let checkpoint2 = TH.line_of_tok !cur_tok in
    let diffline = (checkpoint2 - checkpoint) in
    let info = mk_info_item file !passed_tokens_last_ckp
    in 

    (match elem with
    | Ast_c.NotParsedCorrectly _ -> stat.bad     <- stat.bad     + diffline
    | _ ->                          stat.correct <- stat.correct + diffline;
    );
    (match elem with
    | Ast_c.FinalDef x -> [(Ast_c.FinalDef x, info)]
    | xs -> (xs, info):: loop ()
    )
  in
  let v = loop() in
  (v, stat)


let parse_print_error_heuristic a  = 
  Common.profile_code "C parsing" (fun () -> parse_print_error_heuristic2 a)
