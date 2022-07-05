/*a.swift*/
func /*a*/a() {}

func /*b*/b(x: String) {
  /*b->a*/a()
  /*b->c*/c()
  /*b->b*/b(x: "test")
}

func /*c*/c() {
  /*c->a*/a()
  if /*c->d*/d() {
    /*c->c*/c()
  }
}

func /*d*/d() -> Bool {
  false
}

/*topLevel->a*/a()
/*topLevel->b*/b(x: "test")
