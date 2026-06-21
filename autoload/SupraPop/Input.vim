vim9script
# Input: text input field
import './Base.vim' as Base

# Constants re-exposed locally for readable bare names
const NOBLOCK  = Base.NOBLOCK
const BLOCK    = Base.BLOCK
const CONTINUE = Base.CONTINUE

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

    var cb_enter:   list<func> = []
    var cb_changed: list<func> = []

    def new(options: dict<any> = {})
        this.type = 'input'
        this._Setup(options)

        if options->has_key('prompt')      | this.prompt      = options.prompt      | endif
        if options->has_key('is_password') | this.is_password = options.is_password | endif

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

    # --- text API ---
    def ClearInput()
        this.input_line = []
        this.cur_pos = 0
        this.max_pos = 0
        this.SetText([this.prompt .. ' '])
        this._ActualiseCursor()
    enddef

    def SetInput(text: string)
        this.input_line = split(text, '\zs')
        this.cur_pos = len(this.input_line)
        this.max_pos = this.cur_pos
        this.SetText([this.prompt .. text .. ' '])
        this._ActualiseCursor()
    enddef

    def GetInput(): string
        return join(this.input_line, '')
    enddef

    # --- overridden hooks ---
    def OnFocusChanged(focus: bool)
        if focus == false
            if this.mid != 0
                matchdelete(this.mid, this.wid)
                this.mid = 0
            endif
        else
            this._ActualiseCursor()
        endif
    enddef

    def HandleClosed()
        if this._timer != 0
            timer_stop(this._timer)
        endif
        super.HandleClosed()
    enddef

    def _ActualiseCursor()
        var hl = 'Cursor'
        if this.mid != 0
            matchdelete(this.mid, this.wid)
        endif
        var hi_end_pos = this.prompt_charlen + 1
        if this.cur_pos > 0
            hi_end_pos += len(join(this.input_line[: this.cur_pos - 1], ''))
        endif
        this.mid = matchaddpos(hl, [[1, hi_end_pos]], 10, -1, {window: this.wid})
    enddef

    def _Redraw()
        if this.is_password
            this.SetText([this.prompt .. repeat('*', len(this.input_line)) .. ' '])
        else
            this.SetText([this.prompt .. join(this.input_line, '') .. ' '])
        endif
    enddef

    # Editing logic (virtual method)
    def OnFocusKey(wid: number, key: string): number
        var ascii = char2nr(key)
        var line  = this.input_line
        var cur   = this.cur_pos
        var maxp  = this.max_pos
        var changed = false

        if (len(key) == 1 && ascii >= 32 && ascii <= 126)
                || (ascii >= 19968 && ascii <= 205743)
            changed = true
            if cur == len(line)
                line->add(key)
            else
                var pre = cur - 1 >= 0 ? line[: cur - 1] : []
                line = pre + [key] + line[cur :]
            endif
            cur += 1
        elseif key == "\<bs>"
            changed = true
            if cur == 0
                return BLOCK
            endif
            if cur == len(line)
                line = line[: -2]
            else
                var before = cur - 2 >= 0 ? line[: cur - 2] : []
                line = before + line[cur :]
            endif
            cur = max([0, cur - 1])
        elseif key == "\<Enter>" || key == "\<CR>"
            var txt = join(copy(this.input_line), '')
            for F in this.cb_enter
                F(this)
            endfor
            return BLOCK
        elseif key == "\<C-v>"
            var content = substitute(getreg('"'), '\n', '', 'g')
            if len(content) == 0
                return NOBLOCK
            endif
            changed = true
            var chars = split(content, '\zs')
            if cur == len(line)
                line += chars
            else
                var pre = cur - 1 >= 0 ? line[: cur - 1] : []
                line = pre + chars + line[cur :]
            endif
            cur += len(chars)
        elseif key == "\<Left>"
            cur = max([0, cur - 1])
        elseif key == "\<Right>"
            cur = min([maxp, cur + 1])
        elseif key == "\<End>"
            cur = maxp
        elseif key == "\<Home>"
            cur = 0
        elseif key ==? "\<Del>"
            changed = true
            if cur == maxp
                return BLOCK
            endif
            if cur == 0
                line = line[1 :]
            else
                var before = cur - 1 >= 0 ? line[: cur - 1] : []
                line = before + line[cur + 1 :]
            endif
        elseif key ==? "\<LeftMouse>" || key ==? "\<2-LeftMouse>"
            var mp = getmousepos()
            if mp.winid != wid
                return NOBLOCK
            endif
            cur = mp.wincol - this.prompt_charlen - 1
            cur = max([0, min([maxp, cur])])
        else
            return NOBLOCK
        endif

        this.input_line = line
        this.cur_pos    = cur
        this.max_pos    = len(line)
        this._Redraw()
        this._ActualiseCursor()

        if changed
            if len(this.cb_changed) == 0
                return BLOCK
            endif
            var txt = len(this.input_line) == 0 ? '' : join(copy(this.input_line), '')
            for F in this.cb_changed
                F(this, key, txt)
            endfor
        endif
        return BLOCK
    enddef
endclass
