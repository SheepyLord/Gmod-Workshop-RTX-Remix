// A stand-in materialsystem.dll for the engine guard's end-to-end test (ADR 0130). Its code is
// fake_materialsystem.asm: one function whose machine code holds the call site the guard looks for, as
// CMaterial::InitializeShader has it (the key values in r13, the material in r14), calling a stand-in
// KeyValues::GetString that returns the first field of its key values. This file exports its address.
extern "C" void nl_fake_initialize();

extern "C" __declspec(dllexport) const void* nl_fake_initialize_code() {
  return reinterpret_cast<const void*>(&nl_fake_initialize);
}
