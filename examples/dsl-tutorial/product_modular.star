load("model.star", "make_product")

make_product(int(args.get("release_sequence", "1")))
