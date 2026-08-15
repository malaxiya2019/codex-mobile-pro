// 冒烟测试（需先装真实依赖）：
//   npm install --no-save @deepseek-ai/dsh-tools @deepseek-ai/cordis
// 验证 apply() 用真实 defineTool 注册成功 + execute() 数据正确。
import assert from 'node:assert/strict'

let defineTool
try {
  ({ defineTool } = await import('@deepseek-ai/dsh-tools'))
} catch {
  console.error('[smoke] missing @deepseek-ai/dsh-tools — run: npm install --no-save @deepseek-ai/dsh-tools @deepseek-ai/cordis')
  process.exit(1)
}

const registered = []
const ctx = { tools: { register: (def) => registered.push(def) } }

const mod = await import('../index.js')
assert.equal(mod.name, 'cmp-skill-index')
assert.deepEqual(mod.inject, ['tools'])
await mod.apply(ctx) // 真实 defineTool 校验定义，抛错即暴露

assert.equal(registered.length, 2, 'expect 2 tools registered')
const byName = Object.fromEntries(registered.map((d) => [d.name, d]))
assert.ok(byName.list_skills, 'list_skills registered')
assert.ok(byName.search_skills, 'search_skills registered')

const all = await byName.list_skills.execute({})
assert.equal(all.length, 70, `expect 70 skills, got ${all.length}`)
assert.ok(all.every((s) => s.name && s.description), 'every item has name+description')
const lr = byName.list_skills.output.render({}, all)
assert.equal(lr[0].type, 'text')
assert.ok(lr[0].text.startsWith('- ai-slop-cleaner:'), 'render starts with first skill')

const fr = await byName.search_skills.execute({ query: 'frida' })
assert.ok(fr.length > 0 && fr.every((s) => /frida/i.test(s.name + s.description)), 'frida filter ok')
const ob = await byName.search_skills.execute({ query: 'obsidian' })
assert.ok(ob.some((s) => s.name === 'obsidian-vault'), 'obsidian-vault found')
const none = await byName.search_skills.execute({ query: 'zzz-no-such-skill-zzz' })
assert.equal(none.length, 0, 'no-match returns []')
const lim = await byName.search_skills.execute({ query: 'a', limit: 5 })
assert.ok(lim.length <= 5, 'limit respected')

console.log('[smoke] PASS — real @deepseek-ai/dsh-tools validated: 2 tools, 70 skills, list+search+limit+no-match OK')
