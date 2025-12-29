@ Test struct with all bitfield members
struct BitfieldTest {
  @ Single-byte bitfield with three fields
  flags: U8 bitfield { enabled: 1, mode: 2, reserved: 5 }

  @ Two-byte bitfield
  status: [4] U16 bitfield { state: 4, error: 4, code: 8 }
}

@ Struct with mixed bitfield, regular, and array members
struct MixedStruct {
  header: U8 bitfield { version: 3, type: 3, valid: 1, spare: 1 }
  counter: [7] U16
  control: U16 bitfield { enable: 1, mode: 3, priority: 4, reserved: 8 }
  value: F32
}
