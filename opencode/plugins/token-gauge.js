/** @jsxImportSource @opentui/solid */
import { useTerminalDimensions, useStore } from "@opentui/solid"
import { useEvent } from "@opencode-ai/plugin"
import { RGBA } from "@opentui/core"

let sessionTokenUsage = new Map() // sessionID -> {input, output, cacheRead, cacheWrite}
let rateLimited = false
let retryAfterSeconds = 0
let rateLimitErrorTime = 0

export function plugin({ client, kv, state }) {
  // ---- Per-session token accumulation from message.updated events ----
  useEvent("message.updated", (event) => {
    const info = event.properties?.info
    if (!info || info.role !== "assistant") return

    const sid = info.sessionID
    if (!sid) return

    const usage = sessionTokenUsage.get(sid) || { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
    const t = info.tokens
    usage.input += t?.input ?? 0
    usage.output += t?.output ?? 0
    usage.cacheRead += t?.cache?.read ?? 0
    usage.cacheWrite += t?.cache?.write ?? 0
    sessionTokenUsage.set(sid, usage)
  })

  // ---- Detect FreeUsageLimitError / 429 and capture Retry-After ----
  useEvent("session.error", (event) => {
    const props = event.properties
    const err = props?.error
    if (!err) return

    // Check for APIError with statusCode 429
    if (err.name === "APIError" && err.data?.statusCode === 429) {
      const headers = err.data?.responseHeaders
      if (headers && headers["retry-after"]) {
        retryAfterSeconds = parseInt(headers["retry-after"], 10) || 0
      } else {
        // Default: reset at next midnight UTC
        const now = new Date()
        const nextMidnight = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate() + 1,
          0,
          0,
          0,
          0
        )
        retryAfterSeconds = Math.max(1, Math.ceil((nextMidnight - now) / 1000))
      }
      rateLimited = true
      rateLimitErrorTime = Date.now()
    }
  })

  // ---- Render the token gauge in session_prompt_right ----
  return {
    slots: {
      session_prompt_right(ctx, value) {
        const usage = sessionTokenUsage.get(value.session_id) || { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
        const total = usage.input + usage.output + usage.cacheRead + usage.cacheWrite

        let label = ""
        let cooldownText = ""

        if (rateLimited) {
          const elapsed = Math.max(0, Date.now() - rateLimitErrorTime)
          const remaining = Math.max(0, retryAfterSeconds - Math.floor(elapsed / 1000))
          const hours = Math.floor(remaining / 3600)
          const mins = Math.floor((remaining % 3600) / 60)
          const secs = remaining % 60
          cooldownText = ` · refresh in ${hours}h ${mins}m ${secs}s`
          label = `${total} tokens (rate limited)${cooldownText}`
        } else {
          label = `${total} tokens`
        }

        const skin = ctx.theme.current
        return (
          <span
            fg={skin.textMuted}
            style={{ opacity: 0.8 }}
          >
            {label}
          </span>
        )
      },
    },
  }
}