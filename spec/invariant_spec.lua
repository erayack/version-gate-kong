local invariant = require("kong.plugins.version-gate.invariant")

describe("invariant.is_violation", function()
  it("compares large normalized integer strings safely", function()
    assert.is_false(invariant.is_violation("9007199254740993", "9007199254740994"))
    assert.is_true(invariant.is_violation("9007199254740994", "9007199254740993"))
  end)

  it("compares by length before lexicographic order", function()
    assert.is_false(invariant.is_violation("99", "100"))
    assert.is_true(invariant.is_violation("100", "99"))
  end)
end)
