import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dropdown"
export default class extends Controller {
  static targets = ["menu"]
  
  connect() {
    this.outsideClickHandler = this.handleOutsideClick.bind(this)
  }
  
  disconnect() {
    document.removeEventListener("click", this.outsideClickHandler)
  }
  
  toggle(event) {
    event.stopPropagation()
    
    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }
  
  open() {
    this.menuTarget.classList.remove("hidden")
    document.addEventListener("click", this.outsideClickHandler)
  }
  
  close() {
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this.outsideClickHandler)
  }
  
  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
}
