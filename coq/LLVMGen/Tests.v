Require Import Coq.Strings.String.
Require Import Coq.Lists.List.

Require Import Helix.FSigmaHCOL.FSigmaHCOL.
Require Import Vellvm.Numeric.Fappli_IEEE_extra.

Require Import Flocq.IEEE754.Binary.
Require Import Flocq.IEEE754.Bits.

Require Import Coq.Numbers.BinNums. (* for Z scope *)
Require Import Coq.ZArith.BinInt.

Require Import ExtLib.Structures.Monads.
Require Import Vellvm.LLVMIO.
Require Import Vellvm.StepSemantics.
Require Import Vellvm.Memory.
Require Import Vellvm.LLVMAst.
Require Import Helix.LLVMGen.Compiler.

Import ListNotations.

Program Definition FloatV32Zero := Float32V (@FF2B _ _ (F754_zero false) _).
Program Definition FloatV32One := Float32V (BofZ _ _ _ _ 1%Z).
Next Obligation. reflexivity. Qed.
Next Obligation. reflexivity. Qed.

Section DoubleTests.
  Program Definition FloatV64Zero := Float64V (@FF2B _ _ (F754_zero false) _).

  Program Definition FloatV64One := Float64V (BofZ _ _ _ _ 1%Z).
  Next Obligation. reflexivity. Qed.
  Next Obligation. reflexivity. Qed.

  (* sample definition to be moved to DynWin.v *)
  Definition DynWin64_test: @FSHOperator Float64 (1 + 4) 1 :=
    FSHCompose (FSHBinOp (AZless (AVar 1) (AVar 0)))
     (FSHHTSUMUnion (APlus (AVar 1) (AVar 0))
        (FSHCompose (FSHeUnion (NConst 0) FloatV64Zero)
           (FSHIReduction 3 (APlus (AVar 1) (AVar 0)) FloatV64Zero
              (FSHCompose
                 (FSHCompose (FSHPointwise (AMult (AVar 0) (ANth 3 (VVar 3) (NVar 2))))
                    (FSHInductor (NVar 0) (AMult (AVar 1) (AVar 0)) FloatV64One))
                 (FSHeT (NConst 0)))))
        (FSHCompose (FSHeUnion (NConst 1) FloatV64Zero)
           (FSHIReduction 2 (AMax (AVar 1) (AVar 0)) FloatV64Zero
              (FSHCompose (FSHBinOp (AAbs (AMinus (AVar 1) (AVar 0))))
                 (FSHIUnion 2 (APlus (AVar 1) (AVar 0)) FloatV64Zero
                    (FSHCompose (FSHeUnion (NVar 0) FloatV64Zero)
                       (FSHeT
                          (NPlus (NPlus (NConst 1) (NMult (NVar 1) (NConst 1)))
                             (NMult (NVar 0) (NMult (NConst 2) (NConst 1))))))))))).

  Definition BinOp_less_test: @FSHOperator Float64 (2+2) 2 :=
    FSHBinOp (AZless (AVar 1) (AVar 0)).

  Definition BinOp_plus_test: @FSHOperator Float64 (2+2) 2 :=
    FSHBinOp (APlus (AVar 1) (AVar 0)).

  Definition Pointwise_plus1_test: @FSHOperator Float64 8 8 :=
    FSHPointwise (APlus (AConst FloatV64One) (AVar 0)).

  Definition Pointwise_plusD_test: @FSHOperator Float64 8 8 :=
    FSHPointwise (APlus (AVar 0) (AVar 2)).

  Definition Compose_pointwise_test: @FSHOperator Float64 8 8 :=
    FSHCompose Pointwise_plus1_test Pointwise_plus1_test.

  Record FSHCOLTest :=
    mkFSHCOLTest
      {
        ft: FloatT;
        i: nat;
        o: nat;
        name: string;
        globals: list (string * (@FSHValType ft)) ;
        op: @FSHOperator ft i o;
      }.

  Definition IReduction_test: @FSHOperator Float64 4 4 :=
    FSHIReduction 3 (APlus (AVar 1) (AVar 0)) FloatV64Zero FSHId.

  Definition IUnion_test: @FSHOperator Float64 4 4 :=
    FSHIUnion 4 (APlus (AVar 1) (AVar 0)) FloatV64Zero
              (FSHCompose
                 (FSHeUnion (NVar 0) FloatV64Zero)
                 (FSHCompose
                    FSHId
                    (FSHeT (NVar 0)))).

  Definition Inductor_test: @FSHOperator Float64 1 1 :=
    FSHInductor (NConst 8) (AMult (AVar 1) (AVar 0)) FloatV64One.

  Definition SUMUnionTest: @FSHOperator Float64 4 4 :=
    FSHHTSUMUnion (APlus (AVar 1) (AVar 0)) FSHId FSHId.


End DoubleTests.

Section SingleTests.
  (* sample definition to be moved to DynWin.v *)
  Definition DynWin32_test: @FSHOperator Float32 (1 + 4) 1 :=
    FSHCompose (FSHBinOp (AZless (AVar 1) (AVar 0)))
     (FSHHTSUMUnion (APlus (AVar 1) (AVar 0))
        (FSHCompose (FSHeUnion (NConst 0) FloatV32Zero)
           (FSHIReduction 3 (APlus (AVar 1) (AVar 0)) FloatV32Zero
              (FSHCompose
                 (FSHCompose (FSHPointwise (AMult (AVar 0) (ANth 3 (VVar 3) (NVar 2))))
                    (FSHInductor (NVar 0) (AMult (AVar 1) (AVar 0)) FloatV32One))
                 (FSHeT (NConst 0)))))
        (FSHCompose (FSHeUnion (NConst 1) FloatV32Zero)
           (FSHIReduction 2 (AMax (AVar 1) (AVar 0)) FloatV32Zero
              (FSHCompose (FSHBinOp (AAbs (AMinus (AVar 1) (AVar 0))))
                 (FSHIUnion 2 (APlus (AVar 1) (AVar 0)) FloatV32Zero
                    (FSHCompose (FSHeUnion (NVar 0) FloatV32Zero)
                       (FSHeT
                          (NPlus (NPlus (NConst 1) (NMult (NVar 1) (NConst 1)))
                             (NMult (NVar 0) (NMult (NConst 2) (NConst 1))))))))))).

End SingleTests.

Local Open Scope string_scope.

Definition all_tests :=
  [
    {| name:="dynwin64"; op:=DynWin64_test ; globals:=[("D", @FSHvecValType Float64 3)] |} ;
      {| name:="dynwin32"; op:=DynWin32_test ; globals:=[("D", @FSHvecValType Float32 3)] |} ;
      {| name:="binop_less"; op:=BinOp_less_test; globals:=[] |} ;
      {| name:="binop_plus"; op:=BinOp_plus_test; globals:=[] |} ;
      {| name:="ireduction"; op:=IReduction_test; globals:=[] |} ;
      {| name:="iunion"; op:=IUnion_test; globals:=[] |} ;
      {| name:="inductor"; op:=Inductor_test; globals:=[] |} ;
      {| name:="sumunion"; op:=SUMUnionTest; globals:=[] |} ;
      {| name:="pointwise_plus1"; op:=Pointwise_plus1_test; globals:=[] |} ;
      {| name:="pointwise_plusD"; op:=Pointwise_plusD_test; globals:=[("D", @FSHFloatValType Float64)] |} ;
      {| name:="compose_pointwise"; op:=Compose_pointwise_test ; globals:=[]|}
  ].


Import MonadNotation.

Module IO := LLVMIO.Make(Memory.A).
Module M := Memory.Make(IO).
Module SS := StepSemantics(Memory.A)(IO).

Import IO.
Export IO.DV.

(* Maybe this should go to FSHCOL.v *)
Definition floatTRunType (ft:FloatT): Type :=
  match ft with
  | Float32 => binary32
  | Float64 => binary64
  end.

Definition rotate {A:Type} (default:A) (lst:list (A)): (A*(list A))
  := match lst with
     | [] => (default,[])
     | (x::xs) => (x,app xs [x])
     end.

Definition constArray
           {ft: FloatT}
           (len:nat)
           (data:list (floatTRunType ft)): (list (floatTRunType ft)*list texp).
Admitted.

Definition initIRGlobals
           {ft: FloatT}
           {FnBody: Set}
           (data:list (floatTRunType ft))
           (x: list (string* (@FSHValType ft)))
  : list (toplevel_entity FnBody)
  := let l := List.map
                (fun g:(string* (@FSHValType ft)) =>
                   let (n,t) := g in
                   TLE_Global {|
                       g_ident        := Name n;
                       g_typ          := getIRType t ;
                       g_constant     := true ;
                       g_exp          := None ; (* TODO: fill with random values *)
                       g_linkage      := Some LINKAGE_Internal ;
                       g_visibility   := None ;
                       g_dll_storage  := None ;
                       g_thread_local := None ;
                       g_unnamed_addr := true ;
                       g_addrspace    := None ;
                       g_externally_initialized := false ;
                       g_section      := None ;
                       g_align        := Some Utils.PtrAlignment ;
                     |}
                ) x in
     match l with
     | nil => []
     | cons _ _ => [TLE_Comment _ "Global variables"] ++ l
     end.

Definition genMain
           {ft: FloatT}
           (i o: nat)
           (op_name: string)
           (globals: list (string * (@FSHValType ft)))
           (data:list (floatTRunType ft))
  :
    LLVMAst.toplevel_entities (list LLVMAst.block) :=
  let xtyp := getIRType (@FSHvecValType ft i) in
  let xptyp := TYPE_Pointer xtyp in
  let '(data,xdata) := constArray i data in
  let y := Name "Y" in
  let ytyp := getIRType (@FSHvecValType ft o) in
  let yptyp := TYPE_Pointer ytyp in
  let ftyp := TYPE_Function TYPE_Void [xtyp; ytyp] in
  let fname := Name ("main_" ++ op_name) in
  [
    TLE_Comment _ " Main function" ;
      TLE_Definition
        {|
          df_prototype   :=
            {|
              dc_name        := fname ;
              dc_type        := TYPE_Function ytyp [] ;
              dc_param_attrs := ([],
                                 []);
              dc_linkage     := None ;
              dc_visibility  := None ;
              dc_dll_storage := None ;
              dc_cconv       := None ;
              dc_attrs       := []   ;
              dc_section     := None ;
              dc_align       := None ;
              dc_gc          := None
            |} ;
          df_args        := [];
          df_instrs      := [
                             {|
                               blk_id    := Name "main_block" ;
                               blk_phis  := [];
                               blk_code  :=
                                 (* TODO 0. initialize globals *)
                                 app (@allocTempArrayCode ft y o)
                                     [(IId (Name "op_call"), INSTR_Call (ftyp, EXP_Ident (ID_Local fname)) [(xptyp, EXP_Array xdata)])]
                               ;

                               blk_term  := (IId (Name "main_ret"), TERM_Ret (ytyp, EXP_Ident (ID_Local y))) ;
                               blk_comments := None
                             |}

                           ]
        |}].

Definition runFSHCOLTest (t:FSHCOLTest) (data:list (floatTRunType t.(ft)))
  : option (Trace DV.dvalue)
  :=
    match t return (list (floatTRunType t.(ft)) -> option (Trace DV.dvalue)) with
    | mkFSHCOLTest ft i o name globals op =>
      fun data' =>
        let ginit := initIRGlobals (FnBody:=list block) data' globals in
        let main := genMain i o name globals data' in
        match LLVMGen' (m := sum string) globals false op name with
        | inl _ => None
        | inr prog =>
          let scfg := Vellvm.AstLib.modul_of_toplevel_entities (ginit++main++prog) in
          mcfg <- CFG.mcfg_of_modul scfg ;;
               ret (M.memD M.empty
                           (s <- SS.init_state mcfg name ;;
                              SS.step_sem mcfg (SS.Step s)))
        end
    end data.
