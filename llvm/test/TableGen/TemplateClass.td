// RUN: llvm-tblgen %s | FileCheck %s
// RUN: llvm-tblgen -DERROR1 %s 2>&1 | FileCheck --check-prefix=ERROR1 %s
// RUN: not llvm-tblgen -DERROR2 %s 2>&1 | FileCheck --check-prefix=ERROR2 %s
// RUN: not llvm-tblgen -DERROR3 %s 2>&1 | FileCheck --check-prefix=ERROR3 %s
// RUN: not llvm-tblgen -DERROR4 %s 2>&1 | FileCheck --check-prefix=ERROR4 %s

// A `template class` whose arguments are used only in ordinary positions must
// behave exactly like a plain class, and identical argument tuples must share
// one instantiation.

class Base<int k> { int K = k; }

template class Simple<int n, string s> : Base<n> {
  int N = n;
  string S = s;
}

def D1 : Simple<1, "a">;
def D2 : Simple<2, "b">;
def D3 : Simple<1, "a">;


// D3 has the same arguments as D1, so it reuses that instantiation.



// Position 1: inheriting from a class-valued template argument, and (falling
// out of the same fix) naming it in type position.

class Fmt<int op> { int Op = op; int W = 0; }
class FmtA<int op> : Fmt<op> { let W = 16; }
class FmtB<int op> : Fmt<op> { let W = 32; }

template class Wrap<class<Fmt> F, int op> : F<op> {
  F self;
}

def WA : Wrap<FmtA, 1>;
def WB : Wrap<FmtB, 2>;




// Positions 2 and 3: a computed bits<n> width and a list-valued bit range.
// Both sides of the assignment are indexed by the same list.

class Encoded { bits<8> Inst; }

template class Splice<int width, list<int> slice> : Encoded {
  bits<width> enc;
  let Inst{slice} = enc{slice};
}

def S1 : Splice<8, !listconcat(!range(6, 8), !range(0, 2))>;



// The instantiated body must not absorb the let stack of the use site: the
// class is cached and reused by uses outside that `let`.

class Fields { int X = 0; int Y = 0; }
template class Plain<int n> : Fields { int N = n; }

let X = 1 in {
  def InLet : Plain<7>;
}
def OutLet : Plain<7>;




// Defs are printed in name order, so every expectation lives here in that
// order rather than beside the definition it describes.

// CHECK:      def D1 {	// Base Simple Simple$0
// CHECK-NEXT:   int K = 1;
// CHECK-NEXT:   int N = 1;
// CHECK-NEXT:   string S = "a";

// CHECK:      def D2 {	// Base Simple Simple$1
// CHECK-NEXT:   int K = 2;
// CHECK-NEXT:   int N = 2;
// CHECK-NEXT:   string S = "b";

// D3 has the same arguments as D1, so it shares that instantiation.
// CHECK:      def D3 {	// Base Simple Simple$0
// CHECK-NEXT:   int K = 1;
// CHECK-NEXT:   int N = 1;
// CHECK-NEXT:   string S = "a";

// InLet and OutLet share one cached class, but only InLet picks up the let.
// CHECK:      def InLet {	// Fields Plain Plain$0
// CHECK-NEXT:   int X = 1;
// CHECK-NEXT:   int Y = 0;
// CHECK-NEXT:   int N = 7;

// CHECK:      def OutLet {	// Fields Plain Plain$0
// CHECK-NEXT:   int X = 0;
// CHECK-NEXT:   int Y = 0;
// CHECK-NEXT:   int N = 7;

// CHECK:      def S1 {	// Encoded Splice Splice$0
// CHECK-NEXT:   bits<8> Inst = { enc{7}, enc{6}, ?, ?, ?, ?, enc{1}, enc{0} };
// CHECK-NEXT:   bits<8> enc = { ?, ?, ?, ?, ?, ?, ?, ? };

// CHECK:      def Shadow {
// CHECK-NEXT:   string Self = "Shadow";

// CHECK:      def WA {	// Fmt FmtA Wrap Wrap$0
// CHECK-NEXT:   int Op = 1;
// CHECK-NEXT:   int W = 16;
// CHECK-NEXT:   FmtA self = ?;

// CHECK:      def WB {	// Fmt FmtB Wrap Wrap$1
// CHECK-NEXT:   int Op = 2;
// CHECK-NEXT:   int W = 32;
// CHECK-NEXT:   FmtB self = ?;


// A class named in value position is a last resort: a def of the same name
// still wins, so this does not change what existing .td files mean.
class Shadow { int Z = 1; }
def Shadow { string Self = !cast<string>(Shadow); }

#ifdef ERROR1
// An unbounded `class` argument accepts any class.
class Unrelated { int Z = 9; }
template class AnyClass<class F> { F f; }
def AC1 : AnyClass<Fmt>;
def AC2 : AnyClass<Unrelated>;
// ERROR1: def AC2 {	// AnyClass AnyClass$1
// ERROR1-NEXT: Unrelated f = ?;
#endif

#ifdef ERROR2
// A bounded `class<Fmt>` rejects a class that does not satisfy the bound.
class Outside { int Z = 9; }
def Bad : Wrap<Outside, 1>;
// ERROR2: error: Value specified for template argument 'Wrap:F' is of type class<Outside>; expected type class<Fmt>
#endif

#ifdef ERROR3
// Recursion is caught rather than run out of stack.
template class Recur<int n> : Recur<n> { int N = n; }
def R : Recur<1>;
// ERROR3: error: template class instantiation nested more than 64 deep while instantiating 'Recur'; is it recursive?
#endif

#ifdef ERROR4
// The name of a template class is reserved the way a class name is.
template class Dup<int n> { int N = n; }
template class Dup<int n> { int N = n; }
// ERROR4: error: template class 'Dup' already defined
#endif
