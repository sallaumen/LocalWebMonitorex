// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/local_web_monitorex"
import topbar from "../vendor/topbar"
import {readTheme, resolveTheme, saveTheme} from "./theme.mjs"

const PreviewDialog = {
  mounted() {
    this.returnFocus = document.activeElement
    this.onCancel = event => {
      event.preventDefault()
      this.pushEvent("close_preview", {})
    }
    this.onBackdropClick = event => {
      const bounds = this.el.getBoundingClientRect()
      const outside = event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom
      if (event.target === this.el && outside) this.pushEvent("close_preview", {})
    }
    this.el.addEventListener("cancel", this.onCancel)
    this.el.addEventListener("click", this.onBackdropClick)
    this.el.showModal()
    this.el.querySelector("[data-preview-close]").focus()
  },
  updated() {
    const image = this.el.querySelector(".preview-frame img")
    if (image && image.getAttribute("src") !== this.el.dataset.previewSrc) {
      image.src = this.el.dataset.previewSrc
    }
  },
  destroyed() {
    requestAnimationFrame(() => {
      const trigger = document.querySelector(`button[phx-click="open_preview"][phx-value-port="${this.el.dataset.previewPort}"]`)
      const fallback = document.querySelector("#service-filter input")
      const focusTarget = trigger || (this.returnFocus?.isConnected ? this.returnFocus : null) || fallback
      focusTarget?.focus()
    })
  },
}

const themeQuery = window.matchMedia("(prefers-color-scheme: dark)")

const ThemePreferences = {
  mounted() {
    this.preference = readTheme(() => window.localStorage)
    this.persistenceFailed = false
    this.onThemeClick = event => {
      const button = event.target.closest("[data-theme-choice]")
      if (!button || !this.el.contains(button)) return
      this.preference = button.dataset.themeChoice
      this.persistenceFailed = !saveTheme(() => window.localStorage, this.preference)
      this.applyTheme()
    }
    this.onSystemChange = () => {
      if (this.preference === "auto") this.applyTheme()
    }
    this.el.addEventListener("click", this.onThemeClick)
    themeQuery.addEventListener("change", this.onSystemChange)
    this.applyTheme()
  },
  updated() { this.applyTheme() },
  destroyed() {
    this.el.removeEventListener("click", this.onThemeClick)
    themeQuery.removeEventListener("change", this.onSystemChange)
  },
  applyTheme() {
    document.documentElement.dataset.theme = resolveTheme(this.preference, themeQuery.matches)
    this.el.querySelectorAll("[data-theme-choice]").forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.themeChoice === this.preference))
    })
    const warning = this.el.querySelector("[data-theme-storage-warning]")
    if (warning) warning.hidden = !this.persistenceFailed
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, PreviewDialog, ThemePreferences},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
