/*a.swift*/
protocol /*P*/P {}
protocol /*X*/X {}
protocol /*Y*/Y {}
protocol /*Z*/Z {}

class /*A*/A {}
class /*B*/B: A, P {}
class /*C*/C: B {}
class /*D*/D: A {}

struct /*S*/S: P {}
enum /*E*/E: P {}

extension /*extS:X*/S: X {}
extension /*extS*/S {
  func x() {}
}
extension /*extE:Y,Z*/E: Y, Z {}

let a: /*typeA*/A = /*initA*/A()
let s: /*typeS*/S = /*initS*/S()
