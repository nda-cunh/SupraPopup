vim9script
# Button: clickable button
import './Base.vim' as Base

# Constants re-exposed locally for readable bare names
const NOBLOCK  = Base.NOBLOCK
const BLOCK    = Base.BLOCK
const CONTINUE = Base.CONTINUE

export class Button extends Base.SupraPopup
    public var text:       string = ''
    public var text_align: string = 'center'

    var cb_click: list<func> = []

    def new(options: dict<any> = {})
        this.type = 'button'
        this._Setup(options)
        if options->has_key('text')       | this.text       = options.text       | endif
        if options->has_key('text_align') | this.text_align = options.text_align | endif
        this.SetText([this.text])
    enddef

    def AddEventButtonClick(F: func): func
        add(this.cb_click, F)
        return F
    enddef

    # Center the text by overriding SetText
    def SetText(text: list<string>)
        var raw = join(text, '')
        var w = this.width
        if this.text_align == 'center' && len(raw) < w
            var space = (w - len(raw)) / 2
            raw = repeat(' ', space) .. raw .. repeat(' ', w - space - len(raw))
        endif
        popup_settext(this.wid, [raw])
        this._ActualizeSize()
        this.SetTitle(this.title)
    enddef

    def OnFocusChanged(focus: bool)
        if focus
            popup_setoptions(this.wid, {
                borderchars: ['═', '║', '═', '║', '╔', '╗', '╝', '╚'],
            })
        else
            popup_setoptions(this.wid, {
                borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
            })
        endif
    enddef

    def _Fire()
        for F in this.cb_click
            F(this)
        endfor
    enddef

    def OnNoFocusKey(wid: number, key: string): number
        if key ==? "\<LeftMouse>" || key ==? "\<2-LeftMouse>"
            var mp = getmousepos()
            if mp.winid == wid
                this._Fire()
                this.SetFocus(true)
                return BLOCK
            endif
        endif
        return super.OnNoFocusKey(wid, key)
    enddef

    def OnFocusKey(wid: number, key: string): number
        if key ==? "\<Enter>" || key ==? "\<CR>"
            this._Fire()
            return BLOCK
        endif
        return NOBLOCK
    enddef
endclass
