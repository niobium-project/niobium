(component
  (core module $m
    (func (export "exact") (param i64) (result i64) local.get 0))
  (core instance $i (instantiate $m))
  (alias core export $i "exact" (core func $exact))
  (func (export "exact") (param "value" u64) (result u64)
    (canon lift (core func $exact))))
