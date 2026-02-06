let run () =
  let program = Fixture.build_kv_store_ast () in
  let analysis = Fixture.analyze_exn program in
  let config = Fixture.compile_exn analysis in
  let output = Cloudlang.generate config in

  assert (Fixture.has_substr output {|"name": "storage"|});
  assert (Fixture.has_substr output {|"name": "cache"|});
  assert (Fixture.has_substr output {|"name": "handleRequest"|});

  assert (Fixture.has_substr output {|"binding": "STORE"|});
  assert (Fixture.has_substr output {|"id": "cloudlang-store"|});
  assert (Fixture.has_substr output {|"binding": "CACHE"|});
  assert (Fixture.has_substr output {|"id": "cloudlang-cache"|});

  assert (Fixture.has_substr output {|"service": "storage"|});
  assert (Fixture.has_substr output {|"service": "cache"|});

  assert (Fixture.has_substr output {|"/handleRequest"|});

  assert (Fixture.has_substr output "interface Env");
  assert (Fixture.has_substr output "async fetch");
  assert (Fixture.has_substr output "export default")
