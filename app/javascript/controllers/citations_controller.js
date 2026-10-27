import { Controller } from "@hotwired/stimulus"

// Tailwind's lg breakpoint, where _answered switches from stacked cards to the rail.
const RAIL = "(min-width: 64rem)"
const SWIPE_DISTANCE = 50

// Enhances an answer's citations. Without JavaScript, markers link to their source cards
// and every passage shows. With it, at lg and wider the cards form an accordion in the
// rail; below lg, a marker or card opens its source in a non-modal bottom sheet. Lives
// on the answered section, so a broadcast that replaces the section reconnects it.
export default class extends Controller {
  static targets = [ "marker", "card", "header", "cardButton", "sheet", "sheetNumber", "sheetTitle", "sheetPath",
                     "sheetPassage", "pager", "previous", "next", "pageStatus" ]

  connect() {
    this.headerTargets.forEach(header => this.upgrade(header))
    // While the sheet is open, pads the page by its height, so the end of the page can scroll above it.
    this.padding = new ResizeObserver(() => this.element.style.paddingBottom = `${this.sheetTarget.offsetHeight}px`)
    this.media = matchMedia(RAIL)
    this.media.addEventListener("change", this.reset)
    this.reset()
  }

  disconnect() {
    this.media.removeEventListener("change", this.reset)
    this.padding.disconnect()
  }

  selectMarker(event) {
    event.preventDefault()
    const marker = event.currentTarget
    const card = this.cardFor(marker.dataset.sourceNumber)
    const ids = idsOf(marker, "citationIds")

    this.select(card)
    if (this.rail) {
      card.querySelectorAll("blockquote").forEach(passage => passage.toggleAttribute("data-cited", overlaps(passage, ids)))
      card.scrollIntoView({ block: "nearest" })
    } else {
      this.highlight(span => overlaps(span, ids))
      this.openSheet(card, ids, marker)
    }
  }

  selectCard(event) {
    const card = event.currentTarget.closest("[data-source-number]")
    this.select(card)
    if (!this.rail) this.openSheet(card, [], event.currentTarget)
  }

  // Find in page is revealing a collapsed passage.
  reveal(event) {
    if (this.rail) this.select(event.currentTarget.closest("[data-source-number]"))
  }

  closeSheet() {
    if (!this.sheetTarget.open) return

    this.sheetTarget.close()
    this.padding.disconnect()
    this.element.style.paddingBottom = ""
    this.clearSelection()
    this.opener?.focus()
    this.opener = null
  }

  previous() { this.showPage(this.page - 1) }
  next() { this.showPage(this.page + 1) }

  swipeStart(event) {
    this.swipe = event.pointerType === "mouse" ? null : { x: event.clientX, y: event.clientY }
  }

  swipeEnd(event) {
    if (!this.swipe) return
    const dx = event.clientX - this.swipe.x
    const dy = event.clientY - this.swipe.y
    this.swipe = null
    if (Math.abs(dx) > SWIPE_DISTANCE && Math.abs(dx) > Math.abs(dy)) this.showPage(this.page + (dx < 0 ? 1 : -1))
  }

  // Sets up the current mode: the rail starts with source 1 open, the sheet mode with every card closed.
  reset = () => {
    this.closeSheet()
    this.clearSelection()
    this.cardButtonTargets.forEach(button => {
      if (this.rail) button.removeAttribute("aria-haspopup")
      else button.setAttribute("aria-haspopup", "dialog")
      button.setAttribute("aria-controls", this.rail ? this.bodyOf(button.closest("[data-source-number]")).id : this.sheetTarget.id)
    })
    this.cardTargets.forEach((card, index) => this.expand(card, this.rail && index === 0))
  }

  // private

  get rail() { return this.media.matches }

  upgrade(header) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = `${header.className} cursor-pointer`
    button.dataset.citationsTarget = "cardButton"
    button.dataset.action = "citations#selectCard"
    button.append(...header.childNodes)
    header.replaceWith(button)
  }

  // Marks a source as selected: its markers fill, and in the rail its card opens and its spans highlight.
  select(card) {
    const number = card.dataset.sourceNumber
    this.clearSelection()
    this.markerTargets.forEach(marker => marker.toggleAttribute("data-selected", marker.dataset.sourceNumber === number))
    if (this.rail) {
      this.cardTargets.forEach(other => this.expand(other, other === card))
      this.highlight(span => idsOf(span, "sourceNumbers").includes(number))
    }
  }

  expand(card, open) {
    card.toggleAttribute("data-selected", open)
    // until-found keeps collapsed passages reachable by find in page.
    if (open) this.bodyOf(card).removeAttribute("hidden")
    else this.bodyOf(card).setAttribute("hidden", "until-found")
    const button = card.querySelector("[data-citations-target~=cardButton]")
    if (this.rail) button?.setAttribute("aria-expanded", open)
    else button?.removeAttribute("aria-expanded")
  }

  highlight(test) {
    this.element.querySelectorAll("span[data-source-numbers]").forEach(span => span.toggleAttribute("data-highlighted", test(span)))
  }

  clearSelection() {
    for (const name of [ "data-highlighted", "data-cited" ]) {
      this.element.querySelectorAll(`[${name}]`).forEach(element => element.removeAttribute(name))
    }
    this.markerTargets.forEach(marker => marker.removeAttribute("data-selected"))
  }

  openSheet(card, ids, opener) {
    const number = card.dataset.sourceNumber
    this.opener = opener
    this.sheetNumberTarget.textContent = number
    this.sheetTitleTarget.replaceChildren(...card.querySelector(`#source-${number}-title`).cloneNode(true).childNodes)
    this.sheetPathTarget.textContent = card.querySelector(`#source-${number}-path`).textContent
    this.passages = [ ...card.querySelectorAll("blockquote") ].map(passage => {
      const copy = passage.cloneNode(true)
      copy.toggleAttribute("data-cited", overlaps(copy, ids))
      return copy
    })
    this.pagerTarget.hidden = this.passages.length < 2
    this.showPage(Math.max(0, this.passages.findIndex(passage => passage.hasAttribute("data-cited"))))

    if (!this.sheetTarget.open) {
      this.sheetTarget.show()
      this.padding.observe(this.sheetTarget)
    }
    this.sheetTitleTarget.focus()
  }

  showPage(page) {
    if (!this.passages?.[page]) return
    this.page = page
    this.sheetPassageTarget.replaceChildren(this.passages[page])
    this.sheetPassageTarget.scrollTop = 0
    this.pageStatusTarget.textContent = `Passage ${page + 1} of ${this.passages.length}`
    this.previousTarget.disabled = page === 0
    this.nextTarget.disabled = page === this.passages.length - 1
  }

  cardFor(number) {
    return this.cardTargets.find(card => card.dataset.sourceNumber === number)
  }

  bodyOf(card) {
    return card.querySelector(`#source-${card.dataset.sourceNumber}-passages`)
  }
}

function idsOf(element, key) {
  return (element.dataset[key] || "").split(" ").filter(Boolean)
}

function overlaps(element, ids) {
  return idsOf(element, "citationIds").some(id => ids.includes(id))
}
