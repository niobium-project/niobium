;; A real host interface match still carries callable authority outside Component profile 1.
(component
  (type $host (instance
    (type $facts (record (field "os" string) (field "architecture" string)))
    (export "machine-facts" (type $public-facts (eq $facts)))
    (export "facts" (func (result $public-facts)))))
  (import "niobium:host/machine@1.0.0" (instance (type $host)))
  (core module $m
    (func (export "exact") (param i64) (result i64) local.get 0))
  (core instance $i (instantiate $m))
  (alias core export $i "exact" (core func $exact))
  (func (export "exact") (param "value" u64) (result u64)
    (canon lift (core func $exact))))
