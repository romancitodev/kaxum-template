// `sqlx::migrate!` embebe las migraciones al compilar; sin esto cargo no recompila al agregar una nueva.
fn main() {
  println!("cargo:rerun-if-changed=migrations");
}
