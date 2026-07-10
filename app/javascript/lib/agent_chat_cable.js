import { createConsumer } from "@rails/actioncable"

let consumer = null
let subscription = null
const listeners = new Set()

export function subscribeAgentChat(onReceived) {
  listeners.add(onReceived)

  if (!consumer) {
    consumer = createConsumer()
  }

  if (!subscription) {
    subscription = consumer.subscriptions.create("AgentChatAccountChannel", {
      received: (event) => {
        for (const listener of listeners) {
          listener(event)
        }
      }
    })
  }

  return () => {
    listeners.delete(onReceived)
    if (listeners.size === 0) {
      subscription?.unsubscribe()
      subscription = null
      consumer?.disconnect()
      consumer = null
    }
  }
}
