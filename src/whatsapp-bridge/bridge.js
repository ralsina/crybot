#!/usr/bin/env node

/**
 * Crybot WhatsApp Bridge
 *
 * This bridge connects to WhatsApp using the Baileys library (WhatsApp Web protocol)
 * and exposes a WebSocket interface for Crybot to send/receive messages.
 *
 * Usage: node bridge.js [port]
 *   port - WebSocket port (default: 3001)
 *
 * Environment variables:
 *   CRYBOT_WHATSAPP_PORT - Override default port
 *   CRYBOT_WHATSAPP_AUTH_DIR - Directory for auth state (default: ./baileys_auth_info)
 */

import makeWASocket, { useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion, delay } from '@whiskeysockets/baileys'
import { WebSocketServer } from 'ws'
import P from 'pino'
import qrcode from 'qrcode-terminal'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))

// Configuration
const WS_PORT = process.env.CRYBOT_WHATSAPP_PORT || process.argv[2] || 3001
const AUTH_DIR = process.env.CRYBOT_WHATSAPP_AUTH_DIR || join(__dirname, 'baileys_auth_info')

// Simple console logger that's compatible with pino interface
function createLogger(prefix) {
  const log = (level, msg, ...args) => {
    const timestamp = new Date().toISOString().split('T')[1].substring(0, 8)
    const message = typeof msg === 'string' ? msg : JSON.stringify(msg)
    console.log(`[${timestamp}] [${level}]${prefix ? ' [' + prefix + ']' : ''} ${message}`, ...args)
  }

  return {
    info: (msg, ...args) => log('INFO', msg, ...args),
    warn: (msg, ...args) => log('WARN', msg, ...args),
    error: (msg, ...args) => log('ERROR', msg, ...args),
    debug: (msg, ...args) => process.env.LOG_LEVEL === 'debug' || process.env.LOG_LEVEL === 'trace' ? log('DEBUG', msg, ...args) : null,
    trace: (msg, ...args) => process.env.LOG_LEVEL === 'trace' ? log('TRACE', msg, ...args) : null,
    fatal: (msg, ...args) => log('FATAL', msg, ...args),
    child: (opts) => createLogger(opts.module || prefix)
  }
}

const logger = createLogger('Bridge')

// State
let crybotClient = null
let sock = null
let isConnecting = false
let reconnectAttempts = 0
const MAX_RECONNECT_ATTEMPTS = 5
const RECONNECT_DELAY = 5000

/**
 * Send message to connected Crybot client
 */
function sendToCrybot(data) {
  if (crybotClient && crybotClient.readyState === 1) {
    try {
      crybotClient.send(JSON.stringify(data))
    } catch (err) {
      logger.error({ err }, '[Bridge] Failed to send message to Crybot')
    }
  }
}

/**
 * Handle incoming message from WhatsApp
 */
function handleWhatsAppMessage(messages, type) {
  if (type !== 'notify') return

  for (const msg of messages) {
    // Skip messages from self
    if (msg.key.fromMe) continue

    // Extract content
    let content = ''
    if (msg.message?.conversation) {
      content = msg.message.conversation
    } else if (msg.message?.extendedTextMessage?.text) {
      content = msg.message.extendedTextMessage.text
    } else if (msg.message?.imageMessage?.caption) {
      content = `[Image] ${msg.message.imageMessage.caption}`
    } else if (msg.message?.videoMessage?.caption) {
      content = `[Video] ${msg.message.videoMessage.caption}`
    } else if (msg.message?.documentMessage?.caption) {
      content = `[Document] ${msg.message.documentMessage.caption}`
    } else if (msg.message?.audioMessage) {
      content = '[Audio message]'
    } else if (msg.message?.voiceMessage) {
      content = '[Voice message]'
    } else if (msg.message?.protocolMessage) {
      // Protocol messages (edit, delete, etc.) - skip
      continue
    } else {
      // Unknown message type
      content = '[Unsupported message type]'
    }

    // Skip empty content
    if (!content || content.trim() === '') continue

    const jid = msg.key.remoteJid
    const sender = msg.key.participant || msg.key.remoteJid
    const isGroup = jid.endsWith('@g.us')

    // Extract phone number from JID
    const phoneNumber = jid.split('@')[0]

    sendToCrybot({
      type: 'message',
      pn: jid,
      sender: sender,
      content: content,
      id: msg.key.id,
      timestamp: msg.messageTimestamp?.toString() || Date.now().toString(),
      isGroup: isGroup,
      pushName: msg.pushName
    })

    logger.info({
      from: phoneNumber,
      isGroup,
      contentLength: content.length
    }, '[WhatsApp] Received message')
  }
}

/**
 * Start WhatsApp connection
 */
async function startWhatsApp() {
  if (isConnecting) {
    logger.debug('[WhatsApp] Already connecting, skipping')
    return
  }

  isConnecting = true

  try {
    // Fetch latest WhatsApp Web version
    const { version } = await fetchLatestBaileysVersion()
    logger.info({ version: version.join('.') }, '[WhatsApp] Using WA Web version')

    // Get auth state
    const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR)

    // Create socket
    sock = makeWASocket({
      version,
      auth: state,
      logger: logger.child({ module: 'baileys' }),
      markOnlineOnConnect: true,
      connectTimeoutMs: 60000,
      qrTimeout: 0,
      defaultQueryTimeoutMs: undefined,
      keepAliveIntervalMs: 30000
    })

    // Save credentials on update
    sock.ev.on('creds.update', saveCreds)

    // Handle connection updates
    sock.ev.on('connection.update', (update) => {
      const { connection, lastDisconnect, qr } = update

      if (qr) {
        console.log('\n[WhatsApp] QR Code - Scan with WhatsApp Mobile App')
        console.log('[WhatsApp] Open WhatsApp > Settings > Linked Devices > Link a Device\n')
        qrcode.generate(qr, { small: true })
        console.log()
        sendToCrybot({ type: 'qr', code: qr })
      }

      if (connection === 'close') {
        const statusCode = lastDisconnect?.error?.output?.statusCode
        const shouldReconnect = statusCode !== DisconnectReason.loggedOut

        if (statusCode === DisconnectReason.loggedOut) {
          logger.error('[WhatsApp] Logged out - please delete baileys_auth_info and rescan QR')
          sendToCrybot({ type: 'status', status: 'logged_out' })
        } else {
          logger.warn({ statusCode, attempts: reconnectAttempts }, '[WhatsApp] Connection closed')
          sendToCrybot({ type: 'status', status: 'disconnected' })

          if (shouldReconnect && reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            reconnectAttempts++
            logger.info({ delay: RECONNECT_DELAY }, '[WhatsApp] Reconnecting...')
            isConnecting = false
            setTimeout(startWhatsApp, RECONNECT_DELAY)
          } else if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            logger.error('[WhatsApp] Max reconnect attempts reached')
          }
        }
      } else if (connection === 'open') {
        logger.info('[WhatsApp] Connected successfully')
        sendToCrybot({ type: 'status', status: 'connected' })
        reconnectAttempts = 0
      }
    })

    // Handle incoming messages
    sock.ev.on('messages.upsert', handleWhatsAppMessage)

    // Handle message updates (receipts, edits, etc.)
    sock.ev.on('messages.update', (updates) => {
      for (const { key, update } of updates) {
        if (update.pollUpdates) {
          logger.debug({ key }, '[WhatsApp] Poll update received')
        }
      }
    })

    isConnecting = false

  } catch (err) {
    isConnecting = false
    logger.error({ err }, '[WhatsApp] Failed to start connection')
    sendToCrybot({ type: 'error', error: err.message })
  }
}

/**
 * Send message to WhatsApp
 */
async function sendMessageToWhatsApp(jid, content) {
  if (!sock) {
    logger.warn('[WhatsApp] Socket not available')
    return { success: false, error: 'Socket not available' }
  }

  try {
    const message_id = await sock.sendMessage(jid, { text: content })
    logger.info({ to: jid, messageId: message_id }, '[WhatsApp] Sent message')
    return { success: true, id: message_id }
  } catch (err) {
    logger.error({ err, jid }, '[WhatsApp] Failed to send message')
    return { success: false, error: err.message }
  }
}

/**
 * Start WebSocket server for Crybot
 */
function startWebSocketServer() {
  const wss = new WebSocketServer({ port: WS_PORT, host: '127.0.0.1' })

  wss.on('listening', () => {
    logger.info({ port: WS_PORT }, '[Bridge] WebSocket server listening')
  })

  wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress
    logger.info({ ip: clientIp }, '[Bridge] Crybot connected')

    crybotClient = ws

    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data)

        switch (msg.type) {
          case 'send':
            if (msg.jid && msg.content) {
              sendMessageToWhatsApp(msg.jid, msg.content)
            } else {
              logger.warn({ msg }, '[Bridge] Invalid send message')
            }
            break

          case 'ping':
            ws.send(JSON.stringify({ type: 'pong' }))
            break

          default:
            logger.warn({ type: msg.type }, '[Bridge] Unknown message type')
        }
      } catch (err) {
        logger.error({ err }, '[Bridge] Error processing message from Crybot')
      }
    })

    ws.on('close', (code, reason) => {
      logger.info({ code, reason: reason.toString() }, '[Bridge] Crybot disconnected')
      crybotClient = null
    })

    ws.on('error', (err) => {
      logger.error({ err }, '[Bridge] WebSocket error')
    })

    // Send initial status
    ws.send(JSON.stringify({
      type: 'status',
      status: sock?.user ? 'connected' : 'connecting'
    }))
  })

  wss.on('error', (err) => {
    logger.error({ err }, '[Bridge] WebSocket server error')
    process.exit(1)
  })

  return wss
}

/**
 * Main entry point
 */
async function main() {
  logger.info('[Bridge] Starting Crybot WhatsApp Bridge')

  // Start WebSocket server
  startWebSocketServer()

  // Start WhatsApp connection
  await startWhatsApp()

  // Handle graceful shutdown
  process.on('SIGINT', () => {
    logger.info('[Bridge] Shutting down...')
    if (crybotClient) {
      crybotClient.close()
    }
    if (sock) {
      sock.end()
    }
    process.exit(0)
  })

  process.on('SIGTERM', () => {
    logger.info('[Bridge] Received SIGTERM, shutting down...')
    if (crybotClient) {
      crybotClient.close()
    }
    if (sock) {
      sock.end()
    }
    process.exit(0)
  })
}

// Start the bridge
main().catch(err => {
  logger.error({ err }, '[Bridge] Fatal error')
  process.exit(1)
})
