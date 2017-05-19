(* I-code AST *)

type itype = string option

type ivar = Var of string*itype

type iexpr =
  | FunCall of string*(iexpr list)
  | FConst of float
  | IConst of int
  | Loop of ivar*int*int

type istmt =
  | Decl of (ivar list)*istmt
  | Chain of (istmt list)
  | Assign of ivar*iexpr
  | Return of iexpr

(* function definition: name, type, args, body *)
type ifunction = Functoin of string*itype*(ivar list)*istmt

type iprogram = Program of ifunction list
