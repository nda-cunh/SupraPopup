vim9script
# Input: text input field
import './Base.vim' as Base

# Constants re-exposed locally for readable bare names
const NOBLOCK  = Base.NOBLOCK
const BLOCK    = Base.BLOCK
const CONTINUE = Base.CONTINUE

def IsPrintable(key: string): bool
    if strchars(key) != 1 || key[0] == "\x80"
        return false
    endif
    var c = char2nr(key)
    return c >= 32 && c != 127
enddef

export class Input extends Base.SupraPopup
    public var prompt:     string = 'Input: '
    public var is_password: bool  = false

    var input_line:     list<string> = []
    var cur_pos:        number = 0
    var max_pos:        number = 0
    var mid:            number = 0
    var prompt_charlen: number = 0
    var cursor_light:   bool   = true
    var _timer:         number = 0

    # Selection: anchor of the selected range, -1 when there is none.
    # The range is [min(sel_anchor, cur_pos), max(sel_anchor, cur_pos)).
    var sel_anchor:     number = -1
    var sel_mid:        number = 0
    var sel_hl:         string = 'Visual'

    var cb_enter:   list<func> = []
    var cb_changed: list<func> = []
    var cb_redraw:  list<func> = []

    static var _focused:       Input       = null_object
    static var _map_saved:     dict<any>   = {}
    static var _map_installed: bool        = false

    static def CopyFocusedSelection()
        if Input._focused != null_object
            Input._focused.CopySelection()
        endif
    enddef

    def new(options: dict<any> = {})
        this.type = 'input'
        this._Setup(options)

        if options->has_key('prompt')      | this.prompt      = options.prompt      | endif
        if options->has_key('is_password') | this.is_password = options.is_password | endif
        if options->has_key('sel_hl')      | this.sel_hl      = options.sel_hl      | endif

        this.height = 1
        this.prompt_charlen = len(this.prompt)

        this._timer = timer_start(500, (_) => {
            if this.focus == false
                return
            endif
            if this.cursor_light
                if this.mid != 0
                    matchdelete(this.mid, this.wid)
                    this.mid = 0
                endif
            else
                this._ActualiseCursor()
            endif
            this.cursor_light = !this.cursor_light
        }, {repeat: -1})

        this.SetText([this.prompt .. ' '])
        this._ActualiseCursor()
        this.SetFocus(true)
    enddef

    # --- input events ---
    def AddEventInputEnter(F: func): func
        add(this.cb_enter, F)
        return F
    enddef
    def AddEventInputChanged(F: func): func
        add(this.cb_changed, F)
        return F
    enddef
    def AddEventRedraw(F: func): func
        add(this.cb_redraw, F)
        return F
    enddef

    # --- text API ---
    def ClearInput()
        this.input_line = []
        this.cur_pos = 0
        this.max_pos = 0
        this.ClearSelection()
        this.SetText([this.prompt .. ' '])
        this._ActualiseCursor()
    enddef

    def SetInput(text: string)
        this.input_line = split(text, '\zs')
        this.cur_pos = len(this.input_line)
        this.max_pos = this.cur_pos
        this.ClearSelection()
        this.SetText([this.prompt .. text .. ' '])
        this._ActualiseCursor()
    enddef

    def GetInput(): string
        return join(this.input_line, '')
    enddef

    # prompt_charlen is a byte length: _ByteCol() builds match columns from it.
    def SetPrompt(new_prompt: string)
        this.prompt = new_prompt
        this.prompt_charlen = len(new_prompt)
        this._Redraw()
        this._ActualiseSelection()
        this._ActualiseCursor()
    enddef

    def GetPrompt(): string
        return this.prompt
    enddef

    def IsAtEnd(): bool
        return this.cur_pos == this.max_pos
    enddef

    # --- selection API ---
    def HasSelection(): bool
        return this.sel_anchor >= 0 && this.sel_anchor != this.cur_pos
    enddef

    # [start, end) in character indices; [0, 0) when there is no selection.
    def GetSelectionRange(): list<number>
        if !this.HasSelection()
            return [0, 0]
        endif
        return [min([this.sel_anchor, this.cur_pos]), max([this.sel_anchor, this.cur_pos])]
    enddef

    def GetSelection(): string
        var [s, e] = this.GetSelectionRange()
        if s == e
            return ''
        endif
        return join(this.input_line[s : e - 1], '')
    enddef

    def SelectAll()
        this.sel_anchor = 0
        this.cur_pos    = this.max_pos
        this._ActualiseSelection()
        this._ActualiseCursor()
    enddef

    def ClearSelection()
        this.sel_anchor = -1
        this._ActualiseSelection()
    enddef

    def DeleteSelection(): bool
        var [s, e] = this.GetSelectionRange()
        if s == e
            return false
        endif
        var before = s > 0 ? this.input_line[: s - 1] : []
        this.input_line = before + this.input_line[e :]
        this.cur_pos    = s
        this.max_pos    = len(this.input_line)
        this.sel_anchor = -1
        return true
    enddef

    def CopySelection(): bool
        var txt = this.GetSelection()
        if txt == ''
            return false
        endif
        setreg('"', txt, 'v')
        if has('clipboard')
            setreg('+', txt, 'v')
        endif
        return true
    enddef

    # --- overridden hooks ---
    def OnFocusChanged(focus: bool)
        if focus == false
            if this.mid != 0
                matchdelete(this.mid, this.wid)
                this.mid = 0
            endif
            if this.sel_mid != 0
                matchdelete(this.sel_mid, this.wid)
                this.sel_mid = 0
            endif
            this._ReleaseCopyMap()
        else
            Input._focused = this
            this._InstallCopyMap()
            this._ActualiseSelection()
            this._ActualiseCursor()
        endif
    enddef

    def _InstallCopyMap()
        if Input._map_installed
            return
        endif
        Input._map_installed = true
        Input._map_saved = maparg('<C-C>', 'n', false, true)
        nnoremap <C-C> <Cmd>call g:SupraPopCopyFocused()<CR>
    enddef

    def _ReleaseCopyMap()
        if Input._focused == this
            Input._focused = null_object
        endif
        if !Input._map_installed
            return
        endif
        Input._map_installed = false
        silent! nunmap <C-C>
        if !empty(Input._map_saved)
            mapset('n', false, Input._map_saved)
        endif
        Input._map_saved = {}
    enddef

    def HandleClosed()
        if this._timer != 0
            timer_stop(this._timer)
        endif
        this._ReleaseCopyMap()
        super.HandleClosed()
    enddef

    # Byte column of character index `idx` inside the displayed line.
    # In password mode every char is displayed as a single-byte '*'.
    def _ByteCol(idx: number): number
        if idx <= 0
            return this.prompt_charlen + 1
        endif
        if this.is_password
            return this.prompt_charlen + 1 + idx
        endif
        return this.prompt_charlen + 1 + len(join(this.input_line[: idx - 1], ''))
    enddef

    def _ActualiseCursor()
        var hl = 'Cursor'
        if this.mid != 0
            matchdelete(this.mid, this.wid)
        endif
        this.mid = matchaddpos(hl, [[1, this._ByteCol(this.cur_pos)]], 10, -1, {window: this.wid})
    enddef

    def _ActualiseSelection()
        if this.sel_mid != 0
            matchdelete(this.sel_mid, this.wid)
            this.sel_mid = 0
        endif
        if !this.HasSelection()
            return
        endif
        var [s, e] = this.GetSelectionRange()
        var col = this._ByteCol(s)
        var blen = this._ByteCol(e) - col
        this.sel_mid = matchaddpos(this.sel_hl, [[1, col, blen]], 9, -1, {window: this.wid})
    enddef

    def _InsertChars(chars: list<string>)
        if len(chars) == 0
            return
        endif
        this.DeleteSelection()
        var line = this.input_line
        var cur  = this.cur_pos
        if cur >= len(line)
            line = line + chars
        else
            var pre = cur - 1 >= 0 ? line[: cur - 1] : []
            line = pre + chars + line[cur :]
        endif
        this.input_line = line
        this.cur_pos    = cur + len(chars)
        this.max_pos    = len(line)
    enddef

    # Word boundaries used by C-Left/C-Right and by the selection shortcuts.
    def _WordLeft(from: number): number
        var i = from
        while i > 0 && this.input_line[i - 1] =~ '\s'
            i -= 1
        endwhile
        while i > 0 && this.input_line[i - 1] !~ '\s'
            i -= 1
        endwhile
        return i
    enddef

    def _WordRight(from: number): number
        var i = from
        var n = this.max_pos
        while i < n && this.input_line[i] =~ '\s'
            i += 1
        endwhile
        while i < n && this.input_line[i] !~ '\s'
            i += 1
        endwhile
        return i
    enddef

    # Move the cursor, either extending the selection or dropping it.
    def _MoveTo(pos: number, extend: bool)
        var target = max([0, min([this.max_pos, pos])])
        if extend
            if this.sel_anchor < 0
                this.sel_anchor = this.cur_pos
            endif
        else
            this.sel_anchor = -1
        endif
        this.cur_pos = target
    enddef

    def _FireChanged(key: string)
        if len(this.cb_changed) == 0
            return
        endif
        var txt = join(copy(this.input_line), '')
        for F in this.cb_changed
            F(this, key, txt)
        endfor
    enddef

    def OnPasteKey(key: string)
        if IsPrintable(key)
            this._InsertChars([key])
        endif
    enddef

    def OnPasteEnd()
        this._Redraw()
        this._ActualiseSelection()
        this._ActualiseCursor()
        this._FireChanged("\<PasteEnd>")
    enddef

    def _Redraw()
        if this.is_password
            this.SetText([this.prompt .. repeat('*', len(this.input_line)) .. ' '])
        else
            this.SetText([this.prompt .. join(this.input_line, '') .. ' '])
        endif
        for F in this.cb_redraw
            F(this)
        endfor
    enddef

    def _PosFromMouse(): number
        var mp = getmousepos()
        return max([0, min([this.max_pos, mp.wincol - this.prompt_charlen - 1])])
    enddef

    # Editing logic (virtual method)
    def OnFocusKey(wid: number, key: string): number
        var cur     = this.cur_pos
        var maxp    = this.max_pos
        var changed = false

        if IsPrintable(key)
            this._InsertChars([key])
            changed = true
        elseif key == "\<bs>"
            if this.DeleteSelection()
                changed = true
            elseif cur == 0
                return BLOCK
            else
                var before = cur - 2 >= 0 ? this.input_line[: cur - 2] : []
                this.input_line = before + this.input_line[cur :]
                this.cur_pos    = cur - 1
                this.max_pos    = len(this.input_line)
                changed = true
            endif
        elseif key == "\<Enter>" || key == "\<CR>"
            for F in this.cb_enter
                F(this)
            endfor
            return BLOCK
        elseif key == "\<C-v>"
            var content = substitute(getreg('"'), '\n', '', 'g')
            if len(content) == 0
                return BLOCK
            endif
            this._InsertChars(split(content, '\zs'))
            changed = true
        elseif key == "\<C-a>"
            this.SelectAll()
            this._Redraw()
            return BLOCK
        # C-y, not C-c: Vim force-closes any popup on CTRL-C before the filter
        # is ever invoked (popupwin.c, "Emergency exit"), so it cannot be bound.
        elseif key == "\<C-y>"
            this.CopySelection()
            return BLOCK
        elseif key == "\<C-x>"
            if !this.CopySelection()
                return BLOCK
            endif
            this.DeleteSelection()
            changed = true
        elseif key == "\<Left>"
            if this.HasSelection() | this._MoveTo(this.GetSelectionRange()[0], false)
            else                   | this._MoveTo(cur - 1, false)
            endif
        elseif key == "\<Right>"
            if this.HasSelection() | this._MoveTo(this.GetSelectionRange()[1], false)
            else                   | this._MoveTo(cur + 1, false)
            endif
        elseif key == "\<End>"
            this._MoveTo(maxp, false)
        elseif key == "\<Home>"
            this._MoveTo(0, false)
        elseif key == "\<C-Left>"
            this._MoveTo(this._WordLeft(cur), false)
        elseif key == "\<C-Right>"
            this._MoveTo(this._WordRight(cur), false)
        elseif key == "\<S-Left>"
            this._MoveTo(cur - 1, true)
        elseif key == "\<S-Right>"
            this._MoveTo(cur + 1, true)
        elseif key == "\<S-Home>"
            this._MoveTo(0, true)
        elseif key == "\<S-End>"
            this._MoveTo(maxp, true)
        elseif key == "\<C-S-Left>"
            this._MoveTo(this._WordLeft(cur), true)
        elseif key == "\<C-S-Right>"
            this._MoveTo(this._WordRight(cur), true)
        elseif key ==? "\<Del>"
            if this.DeleteSelection()
                changed = true
            elseif cur == maxp
                return BLOCK
            else
                var before = cur - 1 >= 0 ? this.input_line[: cur - 1] : []
                this.input_line = before + this.input_line[cur + 1 :]
                this.max_pos    = len(this.input_line)
                changed = true
            endif
        elseif key ==? "\<2-LeftMouse>"
            var mp = getmousepos()
            if mp.winid != wid
                return NOBLOCK
            endif
            var pos = this._PosFromMouse()
            this.sel_anchor = this._WordLeft(min([pos + 1, maxp]))
            this.cur_pos    = this._WordRight(this.sel_anchor)
        elseif key ==? "\<LeftMouse>"
            var mp = getmousepos()
            if mp.winid != wid
                return NOBLOCK
            endif
            # Anchor here so a following drag extends the selection.
            this.cur_pos    = this._PosFromMouse()
            this.sel_anchor = this.cur_pos
        elseif key ==? "\<LeftDrag>" || key ==? "\<LeftRelease>"
            var mp = getmousepos()
            if mp.winid != wid
                return NOBLOCK
            endif
            this._MoveTo(this._PosFromMouse(), true)
        else
            return NOBLOCK
        endif

        this._Redraw()
        this._ActualiseSelection()
        this._ActualiseCursor()

        if changed
            this._FireChanged(key)
        endif
        return BLOCK
    enddef
endclass

# Entry point of the <C-C> mapping installed by Input._InstallCopyMap().
g:SupraPopCopyFocused = () => Input.CopyFocusedSelection()
