import type { ReactNode } from 'react'

const URL_SPLIT = /(https?:\/\/[^\s<>]+)/g
const IS_URL = /^https?:\/\/\S+$/
const BULLET = /^\s*[-*\u2022]\s+(.*)$/
const NUMBERED = /^\s*\d+[.)]\s+(.*)$/

function inline(text: string): ReactNode[] {
  return text.split(URL_SPLIT).map((part, i) =>
    IS_URL.test(part) ? (
      <a
        key={i}
        href={part}
        target="_blank"
        rel="noopener noreferrer"
        className="break-all font-medium underline underline-offset-2"
      >
        {part}
      </a>
    ) : (
      part
    ),
  )
}

type Block =
  | { kind: 'p'; lines: string[] }
  | { kind: 'ul'; items: string[] }
  | { kind: 'ol'; items: string[] }

function parse(text: string): Block[] {
  const blocks: Block[] = []
  for (const raw of text.replace(/\r\n/g, '\n').split('\n')) {
    const line = raw.trimEnd()
    if (line.trim() === '') {
      blocks.push({ kind: 'p', lines: [] })
      continue
    }
    const bullet = BULLET.exec(line)
    const numbered = NUMBERED.exec(line)
    const last = blocks[blocks.length - 1]
    if (bullet) {
      if (last?.kind === 'ul') last.items.push(bullet[1])
      else blocks.push({ kind: 'ul', items: [bullet[1]] })
    } else if (numbered) {
      if (last?.kind === 'ol') last.items.push(numbered[1])
      else blocks.push({ kind: 'ol', items: [numbered[1]] })
    } else if (last?.kind === 'p') {
      last.lines.push(line)
    } else {
      blocks.push({ kind: 'p', lines: [line] })
    }
  }
  return blocks.filter((b) => (b.kind === 'p' ? b.lines.length > 0 : true))
}

/**
 * Renders plain text with line breaks, bullet and numbered lists, and http(s) links.
 * No HTML is ever injected: text is rendered as React text nodes.
 */
export function RichText({ text, className = '' }: { text: string; className?: string }) {
  const blocks = parse(text)
  return (
    <div className={`space-y-3 text-sm leading-relaxed text-brandHighlight ${className}`}>
      {blocks.map((block, i) => {
        if (block.kind === 'ul') {
          return (
            <ul key={i} className="list-disc space-y-1 pl-5 marker:text-brandHighlight">
              {block.items.map((item, j) => (
                <li key={j}>{inline(item)}</li>
              ))}
            </ul>
          )
        }
        if (block.kind === 'ol') {
          return (
            <ol key={i} className="list-decimal space-y-1 pl-5 marker:font-semibold marker:text-brandHighlight">
              {block.items.map((item, j) => (
                <li key={j}>{inline(item)}</li>
              ))}
            </ol>
          )
        }
        return (
          <p key={i}>
            {block.lines.map((line, j) => (
              <span key={j}>
                {j > 0 && <br />}
                {inline(line)}
              </span>
            ))}
          </p>
        )
      })}
    </div>
  )
}
