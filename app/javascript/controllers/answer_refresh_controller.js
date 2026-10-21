import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Closes the race where the answer is broadcast before the page's stream subscription is
// confirmed. Each time the turbo-cable-stream-source inside gets its "connected" attribute
// (the server confirmed the subscription, so later broadcasts will arrive), this fetches
// the answer's current state once. The server answers 204 while it's still pending.
export default class extends Controller {
  static values = { url: String, section: String }

  connect() {
    this.observer = new MutationObserver(() => this.refresh())
    this.observer.observe(this.element, { subtree: true, attributeFilter: [ "connected" ] })
  }

  disconnect() {
    this.observer.disconnect()
  }

  async refresh() {
    if (!this.element.querySelector("turbo-cable-stream-source[connected]")) return
    if (document.getElementById(this.sectionValue)?.dataset.questionStatus !== "pending") return

    const response = await fetch(this.urlValue, { headers: { Accept: "text/vnd.turbo-stream.html" } })
    if (response.status === 200) Turbo.renderStreamMessage(await response.text())
  }
}
