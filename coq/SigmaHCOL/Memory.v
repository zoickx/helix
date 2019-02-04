(*
  Simple memory model. Inspired by Vellvm

  Memory cells all have the same type: `CarrierA`.
 *)

Require Import Coq.FSets.FMapAVL.
Require Import Structures.OrderedTypeEx.
Require Import Coq.Arith.Peano_dec.

Require Import Helix.HCOL.CarrierType.

Definition addr := (nat * nat) % type.
Definition null := (0, 0).

Open Scope nat_scope.

Lemma addr_dec : forall (a b : addr), {a = b} + {a <> b}.
Proof.
  intros [a1 a2] [b1 b2].
  destruct (eq_nat_dec a1 b1);
    destruct (eq_nat_dec a2 b2); subst.
  - left; reflexivity.
  - right. intros H. inversion H; subst. apply n. reflexivity.
  - right. intros H. inversion H; subst. apply n. reflexivity.
  - right. intros H. inversion H; subst. apply n. reflexivity.
Qed.

Module NM := FMapAVL.Make(Coq.Structures.OrderedTypeEx.Nat_as_OT).
Definition NatMap := NM.t.

Definition mem_add k (v:CarrierA) := NM.add k v.
Definition mem_delete k (m:NatMap CarrierA) := NM.remove k m.
Definition mem_member k (m:NatMap CarrierA) := NM.mem k m.
Definition mem_lookup k (m:NatMap CarrierA) := NM.find k m.
Definition mem_empty := @NM.empty CarrierA.

Definition mem_block := NatMap CarrierA.

(* merge two memory blocks. Return `None` if there is an overlap *)
Definition mem_merge (a b: mem_block) : option (mem_block)
  :=
    NM.fold (fun k v m =>
               match m with
               | None => None
               | Some m' =>
                 if NM.mem k m' then None
                 else Some (NM.add k v m')
               end
            ) a (Some b).

(* merge two memory blocks in (0..n-1) using given operation to combine values *)
Definition mem_merge_with (f: CarrierA -> CarrierA -> CarrierA) (a b: mem_block)
  : mem_block
  :=
    NM.fold (fun k v m =>
               match mem_lookup k m with
               | None => NM.add k v m
               | Some x => NM.add k (f v x) m
               end
            ) a b.

(* block of memory with indices (0..n-1) set to `v` *)
Fixpoint mem_const_block (n:nat) (v: CarrierA) : mem_block
  :=
    match n with
    | O => mem_add n v (mem_empty)
    | S n' => mem_add n v (mem_const_block n' v)
    end.

Definition memory := NatMap mem_block.