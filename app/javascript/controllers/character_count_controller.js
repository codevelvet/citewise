import { Controller } from "@hotwired/stimulus"

// Shows how many characters the question has, out of the textarea's maxlength.
// Without JavaScript the page says "Up to 4,000 characters" and maxlength still holds.
export default class extends Controller {
  static targets = [ "input", "output" ]

  connect() {
    this.update()
  }

  update() {
    const format = (count) => count.toLocaleString("en-US")
    this.outputTarget.textContent = `${format(this.inputTarget.value.length)} / ${format(this.inputTarget.maxLength)} characters`
  }
}
