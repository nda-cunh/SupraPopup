vim9script
# Selector: selectable list
import './Base.vim' as Base

# Constants re-exposed locally for readable bare names
const NOBLOCK  = Base.NOBLOCK
const BLOCK    = Base.BLOCK
const CONTINUE = Base.CONTINUE

export class Selector extends Base.SupraPopup
    var values:      list<string> = []
    var cb_move:     list<func> = []
    var cb_select:   list<func> = []

    def new(options: dict<any> = {}, values: list<string> = [])
        this.type = 'selector'
        this.cursorline = 1
        this._Setup(options)
        this.values = values
        this.SetSize(this.width, len(values))
        this.SetText(values)
    enddef

    def AddEventSelectorMove(F: func): func
        add(this.cb_move, F)
        return F
    enddef
    def AddEventSelectorSelect(F: func): func
        add(this.cb_select, F)
        return F
    enddef

    def _LineText(wid: number): string
        var buf = winbufnr(this.wid)
        var l = line('.', wid)
        return getbufline(buf, l, l)[0]
    enddef

    # Keyboard nav ONLY when the selector has focus, otherwise these keys must
    # reach the focused popup (e.g. a neighbor Input's Enter). In OnNoFocusKey
    # an unfocused selector would swallow the Enter meant for an input field.
    def OnFocusKey(wid: number, key: string): number
        if key ==? "\<Up>"
            win_execute(this.wid, 'norm! k')
            for F in this.cb_move | F(this._LineText(wid)) | endfor
            return BLOCK
        elseif key ==? "\<Down>"
            win_execute(this.wid, 'norm! j')
            for F in this.cb_move | F(this._LineText(wid)) | endfor
            return BLOCK
        elseif key == "\<Enter>" || key ==? "\<CR>"
            for F in this.cb_select | F(this._LineText(wid)) | endfor
            return BLOCK
        endif
        return super.OnFocusKey(wid, key)
    enddef

    # Mouse stays handled without focus (getmousepos targets a precise window),
    # but we only consume clicks that hit THIS selector.
    def OnNoFocusKey(wid: number, key: string): number
        if key ==? "\<LeftMouse>" || key ==? "\<2-LeftMouse>"
            var mp = getmousepos()
            if mp.winid == wid
                win_execute(wid, 'norm! ' .. mp.line .. 'G')
                this.SetFocus(true)
                for F in this.cb_select | F(this._LineText(wid)) | endfor
                return BLOCK
            endif
        endif
        return super.OnNoFocusKey(wid, key)
    enddef
endclass
