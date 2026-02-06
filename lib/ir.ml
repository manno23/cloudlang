type binding =
  | D1Binding of { name : string; database_id : string }
  | KVBinding of { name : string; namespace_id : string }
  | R2Binding of { name : string; bucket_name : string }
  | ServiceBinding of { name : string; service : string }

type worker = {
  name : string;
  script : string;
  bindings : binding list;
  routes : string list;
}

type durable_object = {
  class_name : string;
  script : string;
}

type r2_bucket = {
  name : string;
  location : string;
}

type d1_database = {
  name : string;
  schema : string;
}

type resource =
  | Worker of worker
  | DurableObject of durable_object
  | R2Bucket of r2_bucket
  | D1Database of d1_database

type config = resource list
