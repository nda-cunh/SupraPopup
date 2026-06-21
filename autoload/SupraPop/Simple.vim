vim9script
# Simple: minimal display popup
import './Base.vim' as Base

export class Simple extends Base.SupraPopup
    def new(options: dict<any> = {})
        this.type = 'simple'
        this._Setup(options)
    enddef
endclass
