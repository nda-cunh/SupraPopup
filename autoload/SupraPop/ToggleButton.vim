vim9script
# ToggleButton: on/off stateful button, keeps Button's nav/click
import './Button.vim' as Button

export class ToggleButton extends Button.Button
    public var toggled: bool = false

    # true: a click/Enter toggles the state automatically.
    # false: the app drives the state via SetToggled() (radio-style buttons).
    public var auto_toggle: bool = true

    public var hl_on:  string = 'Cursor'
    public var hl_off: string = 'Normal'

    var cb_toggle: list<func> = []

    def new(options: dict<any> = {})
        this.type = 'togglebutton'
        this._Setup(options)
        if options->has_key('text')        | this.text        = options.text        | endif
        if options->has_key('text_align')  | this.text_align  = options.text_align  | endif
        if options->has_key('toggled')     | this.toggled     = options.toggled     | endif
        if options->has_key('auto_toggle') | this.auto_toggle = options.auto_toggle | endif
        if options->has_key('hl_on')       | this.hl_on       = options.hl_on       | endif
        if options->has_key('hl_off')      | this.hl_off      = options.hl_off      | endif
        this.SetText([this.text])
        this._RefreshBorder()
    enddef

    # --- toggle events ---
    def AddEventToggle(F: func): func
        add(this.cb_toggle, F)
        return F
    enddef
    def RemoveEventToggle(F: func)
        var i = index(this.cb_toggle, F)
        if i >= 0
            remove(this.cb_toggle, i)
        endif
    enddef

    # --- state API ---
    def IsToggled(): bool
        return this.toggled
    enddef

    def SetToggled(state: bool, silent: bool = false)
        if this.toggled == state
            return
        endif
        this.toggled = state
        this._RefreshBorder()
        if !silent
            for F in this.cb_toggle
                F(this, this.toggled)
            endfor
        endif
    enddef

    def Toggle()
        this.SetToggled(!this.toggled)
    enddef

    # Build a highlight group reusing the source group's color as foreground
    # only (no background). For 'Cursor', its block color (bg) becomes the fg.
    def _FgOnlyHl(src: string): string
        var id = synIDtrans(hlID(src))
        var guifg = synIDattr(id, 'bg#', 'gui')
        if guifg == ''
            guifg = synIDattr(id, 'fg#', 'gui')
        endif
        var ctermfg = synIDattr(id, 'bg', 'cterm')
        if ctermfg == ''
            ctermfg = synIDattr(id, 'fg', 'cterm')
        endif
        var name = 'SupraToggle_' .. substitute(src, '\W', '_', 'g')
        var parts = ['gui=NONE', 'cterm=NONE', 'guibg=NONE', 'ctermbg=NONE']
        if guifg != ''   | add(parts, 'guifg=' .. guifg)     | endif
        if ctermfg != '' | add(parts, 'ctermfg=' .. ctermfg) | endif
        execute 'highlight ' .. name .. ' ' .. join(parts, ' ')
        return name
    enddef

    # Border: shape from focus (inherited from Button), color from state.
    def _RefreshBorder()
        var hl = this.toggled ? this._FgOnlyHl(this.hl_on) : this.hl_off
        if this.focus
            popup_setoptions(this.wid, {
                borderchars:     ['═', '║', '═', '║', '╔', '╗', '╝', '╚'],
                borderhighlight: [hl, hl, hl, hl],
            })
        else
            popup_setoptions(this.wid, {
                borderchars:     ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
                borderhighlight: [hl, hl, hl, hl],
            })
        endif
    enddef

    def OnFocusChanged(focus: bool)
        this._RefreshBorder()
    enddef

    # A click/Enter toggles the state (if auto_toggle) then fires Button's clicks
    def _Fire()
        if this.auto_toggle
            this.SetToggled(!this.toggled)
        endif
        super._Fire()
    enddef
endclass
