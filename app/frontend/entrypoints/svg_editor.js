import { Application } from "@hotwired/stimulus"
import MemoSvgEditorController from "../../javascript/controllers/memo_svg_editor_controller.js"
import "../styles/application.css"
import "../styles/svg_editor.css"

const application = Application.start()
application.register("memo-svg-editor", MemoSvgEditorController)
