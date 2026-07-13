vim9script
# =============================================================================
# SupraPopup — base of the popup framework (Vim9 classes). Requires Vim 9.1+.
# Holds the return-code constants, the abstract SupraPopup class and the static
# filter/callback dispatch. Each concrete type lives in its own file and does
# `import './Base.vim'`.
# =============================================================================

# Event handling return codes
export const NOBLOCK:   number = 0  # let other handlers process the key
export const BLOCK:     number = 1  # stop processing the key
export const CONTINUE:  number = 2  # (no-focus) fall through to focus handlers

export abstract class SupraPopup
    # Global registry: wid -> instance, plus the currently focused wid
    static var instances:    dict<any> = {}
    static var focus_actual: number = 0

    static var _map_snapshot: list<dict<any>> = []
    static var _maps_cleared: bool = false

    static def _ClearUserMaps()
        if SupraPopup._maps_cleared
            return
        endif
        SupraPopup._maps_cleared = true
        SupraPopup._map_snapshot = maplist()->filter((_, m) =>
            m.mode =~ '[n ]' && m.lhs !~? '^<Plug>')
        for m in SupraPopup._map_snapshot
            silent! execute (get(m, 'buffer', 0) ? 'nunmap <buffer> ' : 'nunmap ')
                .. substitute(m.lhs, '|', '<Bar>', 'g')
        endfor
    enddef

    static def _RestoreUserMaps()
        if !SupraPopup._maps_cleared
            return
        endif
        SupraPopup._maps_cleared = false
        for m in SupraPopup._map_snapshot
            silent! mapset(m)
        endfor
        SupraPopup._map_snapshot = []
    enddef

    # --- geometry / options ---
    # col/line are `any`: popup_create accepts string positions ("cursor+1").
    # After _Setup they are resolved back to numbers via popup_getpos().
    public var col:       any    = 0
    public var line:      any    = 0
    public var width:     number = 4
    public var height:    number = 1
    public var maxwidth:  number = 999
    public var maxheight: number = 999
    public var pos:       string = 'topleft'
    public var title:     string = ''
    public var title_pos: string = 'center'

    var mapping:    number = 1
    var cursorline: number = 0
    var scrollbar:  number = 0
    var hidden:     number = 0
    var moved:      any = [0, 0, 0]   # list<number> or a string ('WORD', 'any'…)
    var close_key:  list<string> = ["\<Esc>", "\<C-q>"]

    # --- internal state ---
    var wid:      number = 0
    var focus:    bool   = false
    var type:     string = 'simple'
    var _pasting: bool   = false

    # --- Callbacks
    var cb_close:             list<func> = []
    var cb_filter_focus:      list<func> = []
    var cb_filter_nofocus:    list<func> = []
    var cb_gainfocus:         list<func> = []
    var cb_keypressed_focus:  list<func> = []
    var cb_keypressed_nofocus: list<func> = []
    var cb_focus:             func = null_function   # () -> {next, prev} (Tab)

    # =========================================================================
    # Constructor
    # =========================================================================
    def _Setup(options: dict<any>)
        this._ApplyOptions(options)

        this.wid = popup_create([], {
            col:             this.col,
            line:            this.line,
            time:            -1,
            tabpage:         -1,
            zindex:          300,
            hidden:          this.hidden,
            pos:             this.pos,
            drag:            0,
            wrap:            0,
            border:          [1],
            borderhighlight: ['Normal', 'Normal', 'Normal', 'Normal'],
            borderchars:     ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
            highlight:       'Normal',
            padding:         [0, 1, 0, 1],
            mapping:         this.mapping,
            fixed:           1,
            moved:           this.moved,
            cursorline:      this.cursorline,
            scrollbar:       this.scrollbar,
            filter:          (w, k) => SupraPopup.FilterDispatch(w, k),
            callback:        (w, r) => SupraPopup.ClosedDispatch(w, r),
        })

        SupraPopup.instances[this.wid] = this
        SupraPopup._ClearUserMaps()
        this.SetSize(this.width, this.height)

        var p = popup_getpos(this.wid)
        this.width  = p.core_width
        this.height = p.core_height
        this.line   = p.line
        this.col    = p.col
    enddef

    def _ApplyOptions(o: dict<any>)
        if o->has_key('col')        | this.col        = o.col        | endif
        if o->has_key('line')       | this.line       = o.line       | endif
        if o->has_key('width')      | this.width      = o.width      | endif
        if o->has_key('height')     | this.height     = o.height     | endif
        if o->has_key('maxwidth')   | this.maxwidth   = o.maxwidth   | endif
        if o->has_key('maxheight')  | this.maxheight  = o.maxheight  | endif
        if o->has_key('pos')        | this.pos        = o.pos        | endif
        if o->has_key('title')      | this.title      = o.title      | endif
        if o->has_key('title_pos')  | this.title_pos  = o.title_pos  | endif
        if o->has_key('mapping')    | this.mapping    = o.mapping    | endif
        if o->has_key('cursorline') | this.cursorline = o.cursorline | endif
        if o->has_key('scrollbar')  | this.scrollbar  = o.scrollbar  | endif
        if o->has_key('hidden')     | this.hidden     = o.hidden     | endif
        if o->has_key('moved')      | this.moved      = o.moved      | endif
        if o->has_key('close_key')  | this.close_key  = o.close_key  | endif
    enddef

    static def FilterDispatch(wid: number, key: string): number
        if !SupraPopup.instances->has_key(wid)
            return 0
        endif
        return SupraPopup.instances[wid].Filter(wid, key)
    enddef

    static def ClosedDispatch(wid: number, _: any)
        if !SupraPopup.instances->has_key(wid)
            return
        endif
        SupraPopup.instances[wid].HandleClosed()
    enddef

    def _FilterPaste(key: string): number
        if key == "\<PasteStart>"
            this._pasting = true
            return BLOCK
        endif
        if !this._pasting
            return CONTINUE
        endif
        if key == "\<PasteEnd>"
            this._pasting = false
            this.OnPasteEnd()
            return BLOCK
        endif
        this.OnPasteKey(key)
        return BLOCK
    enddef

    def OnPasteKey(key: string)
    enddef

    def OnPasteEnd()
    enddef

    def Filter(wid: number, key: string): number
        if this.focus
            var rp = this._FilterPaste(key)
            if rp != CONTINUE
                return rp
            endif
        endif

        for F in this.cb_keypressed_nofocus
            F(this, key)
        endfor

        for F in this.cb_filter_nofocus
            var ret = F(this, wid, key)
            if ret == NOBLOCK || ret == BLOCK
                return ret
            endif
        endfor

        var rnf = this.OnNoFocusKey(wid, key)
        if rnf == NOBLOCK || rnf == BLOCK
            return rnf
        endif

        if this.focus == false
            return NOBLOCK
        endif

        for F in this.cb_keypressed_focus
            var ret = F(this, key)
            if ret == NOBLOCK || ret == BLOCK
                return ret
            endif
        endfor

        for F in this.cb_filter_focus
            var ret = F(this, wid, key)
            if ret == NOBLOCK || ret == BLOCK
                return ret
            endif
        endfor

        return this.OnFocusKey(wid, key)
    enddef

    def _NavTarget(dir: string): SupraPopup
        var current: SupraPopup = this
        var guard = 0
        while guard < 64
            guard += 1
            if current.cb_focus == null_function
                return null_object
            endif
            var nav = current.cb_focus(current)
            if type(nav) != v:t_dict || !nav->has_key(dir)
                return null_object
            endif
            var nxt: SupraPopup = nav[dir]
            if !nxt.IsHidden()
                return nxt
            endif
            current = nxt
        endwhile
        return null_object
    enddef

    def OnNoFocusKey(wid: number, key: string): number
        if key ==? "\<LeftMouse>"
            var mp = getmousepos()
            if mp.winid == this.wid
                this.SetFocus(true)
            endif
        elseif key == "\<Tab>" || key == "\<S-Tab>"
            if this.focus
                if this.cb_focus != null_function
                    var target = this._NavTarget(key == "\<Tab>" ? 'next' : 'prev')
                    if target != null_object
                        target.SetFocus(true)
                    endif
                endif
                return BLOCK
            endif
        endif

        for k in this.close_key
            if key ==? k
                feedkeys("\<Esc>", 'n')
                popup_close(this.wid)
            endif
        endfor
        return CONTINUE
    enddef

    def OnFocusKey(wid: number, key: string): number
        return NOBLOCK
    enddef

    def OnFocusChanged(focus: bool)
    enddef

    def HandleClosed()
        for F in this.cb_close
            F(this)
        endfor
        if SupraPopup.focus_actual == this.wid
            SupraPopup.focus_actual = 0
        endif
        if SupraPopup.instances->has_key(this.wid)
            remove(SupraPopup.instances, this.wid)
        endif
        if empty(SupraPopup.instances)
            SupraPopup._RestoreUserMaps()
        endif
    enddef

    # =========================================================================
    # Events
    # =========================================================================
    def AddEventClose(F: func): func
        add(this.cb_close, F)
        return F
    enddef

    def RemoveEventClose(F: func)
        var i = index(this.cb_close, F)
        if i >= 0
            remove(this.cb_close, i)
        endif
    enddef

    def AddEventFilterFocus(F: func): func
        add(this.cb_filter_focus, F)
        return F
    enddef

    def AddEventFilterNoFocus(F: func): func
        add(this.cb_filter_nofocus, F)
        return F
    enddef

    def AddEventGetFocus(F: func): func
        add(this.cb_gainfocus, F)
        return F
    enddef

    def AddEventKeyPressedFocus(F: func): func
        add(this.cb_keypressed_focus, F)
        return F
    enddef

    def AddEventKeyPressedNoFocus(F: func): func
        add(this.cb_keypressed_nofocus, F)
        return F
    enddef

    def SetEventFocus(F: func): func
        this.cb_focus = F
        return F
    enddef

    # =========================================================================
    # Utils
    def GetWid(): number
        return this.wid
    enddef

    # =========================================================================
    def SetTitle(title: string)
        this.title = title
        if title == ''
            popup_setoptions(this.wid, {title: title})
            return
        endif
        const title_len = strcharlen(title)
        const w = (this.width - 2) / 2 - title_len / 2
        var new_title: string
        if this.title_pos ==? 'left'
            new_title = ' ' .. title .. ' '
        else
            new_title = repeat('─', w) .. ' ' .. title .. ' '
        endif
        popup_setoptions(this.wid, {title: new_title})
    enddef

    def GetPos(): dict<any>
        return {col: this.col, line: this.line, width: this.width, height: this.height}
    enddef

    def IsOpen(): bool
        return index(popup_list(), this.wid) >= 0
    enddef

    def SetPos(col: number = 0, line: number = 0)
        if col != 0 | this.col = col | endif
        if line != 0 | this.line = line | endif
        if SupraPopup.instances->has_key(this.wid)
            popup_move(this.wid, {col: this.col, line: this.line})
        endif
    enddef

    def SetSize(width: number = -1, height: number = -1)
        popup_move(this.wid, {
            minwidth: width, maxwidth: 999999,
            minheight: height, maxheight: 999999,
        })
        var s = this.GetSize()
        this.width  = s[2]
        this.height = s[3]
        this.SetTitle(this.title)
    enddef

    # [width, height, core_width, core_height]
    def GetSize(): list<number>
        var res = [0, 0, 0, 0]
        if SupraPopup.instances->has_key(this.wid)
            var o = popup_getpos(this.wid)
            res = [o.width, o.height, o.core_width, o.core_height]
        endif
        return res
    enddef

    def _ActualizeSize()
        var s = this.GetSize()
        this.width  = s[2]
        this.height = s[3]
    enddef

    def SetText(text: list<string>)
        popup_settext(this.wid, text)
        this._ActualizeSize()
        this.SetTitle(this.title)
    enddef

    def GetText(start: number = 1, end: number = -1): list<string>
        var buf = winbufnr(this.wid)
        var last: any = end == -1 ? '$' : end
        return getbufline(buf, start, last)
    enddef

    def SetFocus(focus: bool = true, redraw_now: bool = true)
        if this.focus == focus
            return
        endif
        this.focus = focus
        this._pasting = false
        if focus
            if SupraPopup.focus_actual != 0
                && SupraPopup.instances->has_key(SupraPopup.focus_actual)
                SupraPopup.instances[SupraPopup.focus_actual].SetFocus(false, false)
            endif
            SupraPopup.focus_actual = this.wid
            for F in this.cb_gainfocus
                F(this)
            endfor
        endif
        this.OnFocusChanged(focus)
        if redraw_now
            redraw
        endif
    enddef

    def Close()
        if SupraPopup.instances->has_key(this.wid)
            popup_close(this.wid)
        endif
    enddef

    def Hide()
        popup_hide(this.wid)
        this.hidden = 1
    enddef

    def Show()
        popup_show(this.wid)
        this.hidden = 0
    enddef

    def IsHidden(): bool
        return this.hidden == 1
    enddef
endclass
