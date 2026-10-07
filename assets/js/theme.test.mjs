import test from "node:test"
import assert from "node:assert/strict"
import {readTheme, resolveTheme, saveTheme} from "./theme.mjs"

const storage = () => {
  const values = new Map()
  return {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
  }
}

test("follows the operating system until a preference is saved", () => {
  const local = storage()
  assert.equal(readTheme(() => local), "auto")
  assert.equal(resolveTheme(readTheme(() => local), false), "light")
  assert.equal(resolveTheme(readTheme(() => local), true), "dark")
})

test("keeps a manual choice across subsequent reads", () => {
  const local = storage()
  assert.equal(saveTheme(() => local, "dark"), true)
  assert.equal(readTheme(() => local), "dark")
  assert.equal(resolveTheme(readTheme(() => local), false), "dark")

  assert.equal(saveTheme(() => local, "light"), true)
  assert.equal(resolveTheme(readTheme(() => local), true), "light")

  assert.equal(saveTheme(() => local, "auto"), true)
  assert.equal(resolveTheme(readTheme(() => local), true), "dark")
})

test("ignores an invalid saved value and unavailable storage", () => {
  const local = storage()
  local.setItem("localwebmonitorex.theme", "unknown")
  assert.equal(readTheme(() => local), "auto")
  assert.equal(readTheme(() => { throw new Error("denied") }), "auto")
  assert.equal(saveTheme(() => { throw new Error("denied") }, "dark"), false)
})
