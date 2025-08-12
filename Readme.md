# SupraPopup

**SupraPopup** is a **Vim9script** plugin that makes it easy to create interactive popup windows in Vim — whether simple display popups, input fields (`Input`), or soon interactive buttons (`Button`).  
This plugin **only works with Vim9script** and leverages native `popup_*` features by providing a simpler event-driven API.

---

## 🚀 Installation

Using [vim-plug](https://github.com/junegunn/vim-plug):
`vim
Plug 'username/SupraPopup'
`

---

## 📦 Quick Start

Import the module:
`vim
vim9script
import autoload 'supra_popup.vim'

var popup = supra_popup.Input({ title: 'Name', width: 20, height: 1 })
`

---

## 🏗 Constructors

### `Input(options: dict<any> = {}): dict<any>`
Creates an input popup (text field).

### `Simple(options: dict<any>): dict<any>`
Creates a simple popup for displaying text or information.

### `Button(options: dict<any>): dict<any>` *(coming soon)*
Creates an interactive button.

---

## ⚙️ Available Options

All creation functions accept a dictionary of options:

| Option | Type | Default | Description |
|---|---|---|---|
| col | number | 0 | Starting column |
| line | number | 0 | Starting line |
| width | number | 4 | Popup width |
| height | number | 1 | Popup height |
| mapping | number | 0 | Enable mappings (1) |
| maxwidth | number | 999 | Max width |
| maxheight | number | 999 | Max height |
| pos | string | 'topleft' | Relative position |
| title | string | '' | Popup title |
| title_pos | string | 'center' | Title position (left, center, right) |
| cursorline | number | 0 | Cursor line |
| scrollbar | number | 0 | Show scrollbar (1) |
| type | string | 'simple' | Popup type |
| close_key | list<string> | ["<Esc>", "<C-c>", "<C-q>"] | Close shortcuts |
| hidden | number | 0 | Start hidden if 1 |
| ... | ... | ... | See code for all options |

---

## 🔗 Event Handling

Popups support a system of **callbacks** to interact with the user.

Example:
`vim
AddEventClose(popup, (p) => {
    echom 'Popup closed!'
})
`

### Main events
- `AddEventClose` / `RemoveEventClose`
- `AddEventFilterFocus` / `RemoveEventFocus`
- `AddEventFilterNoFocus` / `RemoveEventNoFocus`
- `AddEventGetFocus` / `RemoveEventgetFocus`

### `Input` specific events
- `AddEventInputEnter` / `RemoveEventInputEnter`
- `AddEventInputChanged` / `RemoveEventInputChanged`
- `AddEventKeyPressedFocus` / `RemoveEventKeyPressedFocus`
- `AddEventKeyPressedNoFocus` / `RemoveEventKeyPressedNoFocus`

---

## 🛠 Utility Functions

| Function | Description |
|---|---|
| `SetTitle(popup, title)` | Change the title |
| `GetPos(popup)` | Get popup position |
| `SetPos(popup, col, line)` | Set position |
| `SetSize(popup, width, height)` | Set size |
| `GetSize(popup)` | Returns `[width, height]` |
| `Close(popup)` | Close the popup |
| `SetText(popup, text)` | Set content text |
| `GetText(popup)` | Get content text |
| `SetFocus(popup, focus)` | Give or remove focus |
| `Hide(popup)` / `Show(popup)` | Hide / Show |
| `IsHidden(popup)` | Returns true if hidden |

### Functions for `Input`
- `ClearInput(popup)`
- `SetInput(popup, text)`
- `GetInput(popup)`

---

## 📚 Full Example

Here is an example creating an `Input` field with handling for *Enter* and *Escape* keys:

`vim
vim9script
import autoload 'supra_popup.vim'

def CreateNamePopup()
    var popup = supra_popup.Input({
        title: 'Enter your name',
        width: 30,
        height: 1,
        col: 10,
        line: 5,
        close_key: ["`<Esc>"]
    })

    supra_popup.AddEventInputEnter(popup, (p) => {
        echom 'Name entered: ' .. supra_popup.GetInput(p)
        supra_popup.Close(p)
    })

    supra_popup.AddEventClose(popup, (_) => {
        echom 'Popup closed'
    })
enddef

command! NamePopup CreateNamePopup
`

Then launch:
`vim
:NamePopup
`

You will see an input popup with a title that closes automatically on enter or pressing `Esc`.

---

## 📄 License

MIT — free to use and modify.

