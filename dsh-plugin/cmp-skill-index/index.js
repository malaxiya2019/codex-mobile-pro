// cmp-skill-index — DSH 工具插件：暴露 codex-mobile-pro 的 70 条内置 skill 索引
// 纯 JS、零构建：源码即交付物，git 安装无需 allowBuilds。
import { defineTool } from '@deepseek-ai/dsh-tools'
import { skills } from './data/skills.js'

export const name = 'cmp-skill-index'
export const inject = ['tools']

const SKILL_ITEM = {
  type: 'object',
  additionalProperties: false,
  properties: {
    name: { type: 'string', required: true, description: 'Skill identifier (kebab-case)' },
    description: { type: 'string', required: true, description: 'What the skill does and when to use it' },
  },
}

function matchSkill(skill, query) {
  const q = (query || '').trim().toLowerCase()
  if (!q) return true
  return skill.name.toLowerCase().includes(q)
    || skill.description.toLowerCase().includes(q)
}

function toText(results) {
  if (results.length === 0) return '(no matching skills)'
  return results.map((s) => `- ${s.name}: ${s.description}`).join('\n')
}

export function apply(ctx) {
  ctx.tools.register(defineTool({
    name: 'list_skills',
    description: 'List the preinstalled skill index of codex-mobile-pro (70 skills: code review, TDD, security review, reverse engineering, Obsidian vault, playwright, browser automation, etc.). Returns every skill name + description. Use search_skills for a targeted filter.',
    parameters: {},
    output: {
      schema: { type: 'array', items: SKILL_ITEM },
      render: (_args, value) => [{ type: 'text', text: toText(value) }],
    },
    async execute() {
      return skills
    },
  }))

  ctx.tools.register(defineTool({
    name: 'search_skills',
    description: 'Search the codex-mobile-pro skill index by keyword. Case-insensitive substring match over skill name + description. Returns the matching skills (name + description); an empty array when nothing matches.',
    parameters: {
      query: { type: 'string', required: true, description: 'Keyword(s) to look for in skill name or description' },
      limit: { type: 'number', description: 'Maximum number of results to return (default 20, capped at 50)' },
    },
    output: {
      schema: { type: 'array', items: SKILL_ITEM },
      render: (_args, value) => [{ type: 'text', text: toText(value) }],
    },
    async execute(args) {
      const limit = Math.min(Math.max(args.limit ?? 20, 1), 50)
      return skills.filter((s) => matchSkill(s, args.query)).slice(0, limit)
    },
  }))
}
