param(
    [Parameter(Mandatory)][string]$File,
    [Parameter(Mandatory)][ValidateSet('ast','ssa')][string]$Mode
)

enum TT {
    NUMBER; STRING; TEMPLATE_STRING; BOOL; NULL; UNDEFINED_KW; REGEX
    LET; CONST; VAR; FUNCTION; RETURN; IF; ELSE; WHILE; FOR; OF; IN
    BREAK; CONTINUE; NEW; DELETE; TYPEOF; VOID; INSTANCEOF; AS; THROW
    TRY; CATCH; FINALLY; CLASS; EXTENDS; IMPLEMENTS; INTERFACE; TYPE
    ENUM; IMPORT; EXPORT; FROM; DEFAULT; STATIC; READONLY
    PUBLIC; PRIVATE; PROTECTED; ABSTRACT; DECLARE; NAMESPACE; MODULE
    ASYNC; AWAIT; YIELD; SWITCH; CASE; DO; DEBUGGER
    IDENT
    LPAREN; RPAREN; LBRACE; RBRACE; LBRACKET; RBRACKET
    COMMA; SEMI; COLON; DOT; ELLIPSIS; QUESTION; ARROW; AT
    EQUALS; PLUS_EQ; MINUS_EQ; STAR_EQ; SLASH_EQ; MOD_EQ
    AMP_EQ; PIPE_EQ; CARET_EQ; LSHIFT_EQ; RSHIFT_EQ; URSHIFT_EQ
    STAR_STAR_EQ; AND_EQ; OR_EQ; NULLISH_EQ
    PLUS; MINUS; STAR; SLASH; MOD; STAR_STAR
    EQ_EQ; BANG_EQ; EQ_EQ_EQ; BANG_EQ_EQ
    LT; GT; LT_EQ; GT_EQ
    AMP; PIPE; CARET; TILDE; LSHIFT; RSHIFT; URSHIFT
    AMP_AMP; PIPE_PIPE; BANG
    PLUS_PLUS; MINUS_MINUS
    NULLISH
    OPT_CHAIN
    EOF
}

class Token {
    [TT]$Type
    [string]$Value
    [int]$Line
    [int]$Col

    Token([TT]$t, [string]$v, [int]$line, [int]$col) {
        $this.Type = $t
        $this.Value = $v
        $this.Line = $line
        $this.Col = $col
    }

    [string] ToString() { return "[$($this.Type) '$($this.Value)' L$($this.Line):$($this.Col)]" }
}

class Lexer {
    [string]$Src
    [int]$Pos = 0
    [int]$Line = 1
    [int]$Col = 1

    static [hashtable]$Keywords = @{
        let = [TT]::LET; const = [TT]::CONST; var = [TT]::VAR
        function = [TT]::FUNCTION; return = [TT]::RETURN
        if = [TT]::IF; else = [TT]::ELSE; while = [TT]::WHILE
        for = [TT]::FOR; of = [TT]::OF; 'in' = [TT]::IN
        break = [TT]::BREAK; continue = [TT]::CONTINUE
        new = [TT]::NEW; delete = [TT]::DELETE; typeof = [TT]::TYPEOF
        void = [TT]::VOID; instanceof = [TT]::INSTANCEOF; as = [TT]::AS
        throw = [TT]::THROW; try = [TT]::TRY; catch = [TT]::CATCH
        finally = [TT]::FINALLY; class = [TT]::CLASS; extends = [TT]::EXTENDS
        implements = [TT]::IMPLEMENTS; interface = [TT]::INTERFACE
        type = [TT]::TYPE; enum = [TT]::ENUM; import = [TT]::IMPORT
        export = [TT]::EXPORT; from = [TT]::FROM; default = [TT]::DEFAULT
        static = [TT]::STATIC; readonly = [TT]::READONLY
        public = [TT]::PUBLIC; private = [TT]::PRIVATE; protected = [TT]::PROTECTED
        abstract = [TT]::ABSTRACT; declare = [TT]::DECLARE
        namespace = [TT]::NAMESPACE; module = [TT]::MODULE
        async = [TT]::ASYNC; await = [TT]::AWAIT; yield = [TT]::YIELD
        switch = [TT]::SWITCH; case = [TT]::CASE; do = [TT]::DO
        debugger = [TT]::DEBUGGER; true = [TT]::BOOL; false = [TT]::BOOL
        null = [TT]::NULL; undefined = [TT]::UNDEFINED_KW
    }

    Lexer([string]$src) { $this.Src = $src }

    [char] Peek([int]$offset = 0) {
        $i = $this.Pos + $offset
        if ($i -ge $this.Src.Length) { return [char]0 }
        return $this.Src[$i]
    }

    [void] Advance() {
        if ($this.Pos -lt $this.Src.Length) {
            if ($this.Src[$this.Pos] -eq "`n") { $this.Line++; $this.Col = 1 }
            else { $this.Col++ }
            $this.Pos++
        }
    }

    [Token] MakeToken([TT]$t, [string]$v, [int]$line, [int]$col) {
        return [Token]::new($t, $v, $line, $col)
    }

    [Token[]] Tokenize() {
        $list = [System.Collections.Generic.List[Token]]::new()
        $lastPos = -1

        while ($this.Pos -lt $this.Src.Length) {
            if ($this.Pos -eq $lastPos) { 
                Write-Host "Stuck at Pos=$($this.Pos), Char='$($this.Peek(0))', Line=$($this.Line), Col=$($this.Col)"
                break 
            }
            $lastPos = $this.Pos

            $c = $this.Peek(0)
            $currentLine = $this.Line
            $currentCol = $this.Col

            if ([char]::IsWhiteSpace($c)) { $this.Advance(); continue }

            if ($c -eq '/' -and $this.Peek(1) -eq '/') {
                while ($this.Pos -lt $this.Src.Length -and $this.Peek(0) -ne "`n") { $this.Advance() }
                continue
            }

            if ($c -eq '/' -and $this.Peek(1) -eq '*') {
                $this.Advance(); $this.Advance()
                while ($this.Pos -lt $this.Src.Length) {
                    if ($this.Peek(0) -eq '*' -and $this.Peek(1) -eq '/') { $this.Advance(); $this.Advance(); break }
                    $this.Advance()
                }
                continue
            }

            if ([char]::IsDigit($c) -or ($c -eq '.' -and [char]::IsDigit($this.Peek(1)))) {
                $sb = [System.Text.StringBuilder]::new()
                if ($c -eq '0' -and $this.Peek(1) -in @('x','X')) {
                    [void]$sb.Append($this.Peek(0)); $this.Advance()
                    [void]$sb.Append($this.Peek(0)); $this.Advance()
                    while ($this.Peek(0) -match '[0-9a-fA-F_]') { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                } elseif ($c -eq '0' -and $this.Peek(1) -in @('b','B')) {
                    [void]$sb.Append($this.Peek(0)); $this.Advance()
                    [void]$sb.Append($this.Peek(0)); $this.Advance()
                    while ($this.Peek(0) -match '[01_]') { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                } elseif ($c -eq '0' -and $this.Peek(1) -in @('o','O')) {
                    [void]$sb.Append($this.Peek(0)); $this.Advance()
                    [void]$sb.Append($this.Peek(0)); $this.Advance()
                    while ($this.Peek(0) -match '[0-7_]') { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                } else {
                    while ([char]::IsDigit($this.Peek(0)) -or $this.Peek(0) -eq '_') { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                    if ($this.Peek(0) -eq '.' -and [char]::IsDigit($this.Peek(1))) {
                        [void]$sb.Append($this.Peek(0)); $this.Advance()
                        while ([char]::IsDigit($this.Peek(0)) -or $this.Peek(0) -eq '_') { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                    }
                    if ($this.Peek(0) -in @('e','E')) {
                        [void]$sb.Append($this.Peek(0)); $this.Advance()
                        if ($this.Peek(0) -in @('+','-')) { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                        while ([char]::IsDigit($this.Peek(0))) { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                    }
                    if ($this.Peek(0) -eq 'n') { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                }
                $list.Add($this.MakeToken([TT]::NUMBER, $sb.ToString(), $currentLine, $currentCol))
                continue
            }

            if ($c -in @('"', "'")) {
                $quote = $c; $this.Advance()
                $sb = [System.Text.StringBuilder]::new()
                while ($this.Pos -lt $this.Src.Length -and $this.Peek(0) -ne $quote) {
                    if ($this.Peek(0) -eq '\') {
                        $this.Advance(); $esc = $this.Peek(0); $this.Advance()
                        switch ($esc) {
                            'n' { [void]$sb.Append("`n") }
                            't' { [void]$sb.Append("`t") }
                            'r' { [void]$sb.Append("`r") }
                            '\' { [void]$sb.Append('\') }
                            default { [void]$sb.Append($esc) }
                        }
                    } else { [void]$sb.Append($this.Peek(0)); $this.Advance() }
                }
                $this.Advance()
                $list.Add($this.MakeToken([TT]::STRING, $sb.ToString(), $currentLine, $currentCol))
                continue
            }

            if ($c -eq '`') {
                $this.Advance(); $sb = [System.Text.StringBuilder]::new(); $depth = 0
                while ($this.Pos -lt $this.Src.Length) {
                    $ch = $this.Peek(0)
                    if ($ch -eq '`' -and $depth -eq 0) { $this.Advance(); break }
                    if ($ch -eq '$' -and $this.Peek(1) -eq '{') { $depth++ }
                    if ($ch -eq '}' -and $depth -gt 0) { $depth-- }
                    [void]$sb.Append($ch); $this.Advance()
                }
                $list.Add($this.MakeToken([TT]::TEMPLATE_STRING, $sb.ToString(), $currentLine, $currentCol))
                continue
            }

            if ([char]::IsLetter($c) -or $c -eq '_' -or $c -eq '$') {
                $sb = [System.Text.StringBuilder]::new()
                while ($this.Pos -lt $this.Src.Length -and ([char]::IsLetterOrDigit($this.Peek(0)) -or $this.Peek(0) -in @('_','$'))) {
                    [void]$sb.Append($this.Peek(0)); $this.Advance()
                }
                $text = $sb.ToString()
                if ([Lexer]::Keywords.ContainsKey($text)) {
                    $list.Add($this.MakeToken([Lexer]::Keywords[$text], $text, $currentLine, $currentCol))
                } else {
                    $list.Add($this.MakeToken([TT]::IDENT, $text, $currentLine, $currentCol))
                }
                continue
            }

            $twoChar = "$($this.Peek(0))$($this.Peek(1))"
            $threeChar = "$($this.Peek(0))$($this.Peek(1))$($this.Peek(2))"

            $matched = $true

            if ($c -in @('=','!','.','>','*','&','|','?','<')) {
                switch ($threeChar) {
                    '===' { $list.Add($this.MakeToken([TT]::EQ_EQ_EQ, '===', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '!==' { $list.Add($this.MakeToken([TT]::BANG_EQ_EQ, '!==', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '...' { $list.Add($this.MakeToken([TT]::ELLIPSIS, '...', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '>>>' { $list.Add($this.MakeToken([TT]::URSHIFT, '>>>', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '**=' { $list.Add($this.MakeToken([TT]::STAR_STAR_EQ, '**=', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '&&=' { $list.Add($this.MakeToken([TT]::AND_EQ, '&&=', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '||=' { $list.Add($this.MakeToken([TT]::OR_EQ, '||=', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '??=' { $list.Add($this.MakeToken([TT]::NULLISH_EQ, '??=', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '<<=' { $list.Add($this.MakeToken([TT]::LSHIFT_EQ, '<<=', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    '>>=' { $list.Add($this.MakeToken([TT]::RSHIFT_EQ, '>>=', $currentLine, $currentCol)); $this.Advance(); $this.Advance(); $this.Advance() }
                    default { 
                        $matched = $false; 
                    }
                }
                if ($matched) { continue }
            }
            else {
                $matched = $false
            }

            $matched = $true
            switch ($twoChar) {
                '=>' { $list.Add($this.MakeToken([TT]::ARROW,'=>', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '==' { $list.Add($this.MakeToken([TT]::EQ_EQ,'==', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '!=' { $list.Add($this.MakeToken([TT]::BANG_EQ,'!=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '<=' { $list.Add($this.MakeToken([TT]::LT_EQ,'<=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '>=' { $list.Add($this.MakeToken([TT]::GT_EQ,'>=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '&&' { $list.Add($this.MakeToken([TT]::AMP_AMP,'&&', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '||' { $list.Add($this.MakeToken([TT]::PIPE_PIPE,'||', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '??' { $list.Add($this.MakeToken([TT]::NULLISH,'??', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '?.' { $list.Add($this.MakeToken([TT]::OPT_CHAIN,'?.', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '++' { $list.Add($this.MakeToken([TT]::PLUS_PLUS,'++', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '--' { $list.Add($this.MakeToken([TT]::MINUS_MINUS,'--', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '**' { $list.Add($this.MakeToken([TT]::STAR_STAR, '**', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '+=' { $list.Add($this.MakeToken([TT]::PLUS_EQ, '+=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '-=' { $list.Add($this.MakeToken([TT]::MINUS_EQ, '-=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '*=' { $list.Add($this.MakeToken([TT]::STAR_EQ, '*=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '/=' { $list.Add($this.MakeToken([TT]::SLASH_EQ, '/=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '%=' { $list.Add($this.MakeToken([TT]::MOD_EQ, '%=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '&=' { $list.Add($this.MakeToken([TT]::AMP_EQ, '&=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '|=' { $list.Add($this.MakeToken([TT]::PIPE_EQ, '|=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '^=' { $list.Add($this.MakeToken([TT]::CARET_EQ, '^=', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '<<' { $list.Add($this.MakeToken([TT]::LSHIFT, '<<', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                '>>' { $list.Add($this.MakeToken([TT]::RSHIFT, '>>', $currentLine, $currentCol)); $this.Advance(); $this.Advance() }
                default { 
                    $matched = $false;
                }
            }
            
            if ($matched) { continue }

            switch ($c) {
                '(' { $list.Add($this.MakeToken([TT]::LPAREN, '(', $currentLine, $currentCol)) }
                ')' { $list.Add($this.MakeToken([TT]::RPAREN, ')', $currentLine, $currentCol)) }
                '{' { $list.Add($this.MakeToken([TT]::LBRACE, '{', $currentLine, $currentCol)) }
                '}' { $list.Add($this.MakeToken([TT]::RBRACE, '}', $currentLine, $currentCol)) }
                '[' { $list.Add($this.MakeToken([TT]::LBRACKET, '[', $currentLine, $currentCol)) }
                ']' { $list.Add($this.MakeToken([TT]::RBRACKET, ']', $currentLine, $currentCol)) }
                ',' { $list.Add($this.MakeToken([TT]::COMMA, ',', $currentLine, $currentCol)) }
                ';' { $list.Add($this.MakeToken([TT]::SEMI, ';', $currentLine, $currentCol)) }
                ':' { $list.Add($this.MakeToken([TT]::COLON, ':', $currentLine, $currentCol)) }
                '.' { $list.Add($this.MakeToken([TT]::DOT, '.', $currentLine, $currentCol)) }
                '?' { $list.Add($this.MakeToken([TT]::QUESTION, '?', $currentLine, $currentCol)) }
                '@' { $list.Add($this.MakeToken([TT]::AT, '@', $currentLine, $currentCol)) }
                '+' { $list.Add($this.MakeToken([TT]::PLUS, '+', $currentLine, $currentCol)) }
                '-' { $list.Add($this.MakeToken([TT]::MINUS, '-', $currentLine, $currentCol)) }
                '*' { $list.Add($this.MakeToken([TT]::STAR, '*', $currentLine, $currentCol)) }
                '/' { $list.Add($this.MakeToken([TT]::SLASH, '/', $currentLine, $currentCol)) }
                '%' { $list.Add($this.MakeToken([TT]::MOD, '%', $currentLine, $currentCol)) }
                '=' { $list.Add($this.MakeToken([TT]::EQUALS, '=', $currentLine, $currentCol)) }
                '<' { $list.Add($this.MakeToken([TT]::LT, '<', $currentLine, $currentCol)) }
                '>' { $list.Add($this.MakeToken([TT]::GT, '>', $currentLine, $currentCol)) }
                '&' { $list.Add($this.MakeToken([TT]::AMP, '&', $currentLine, $currentCol)) }
                '|' { $list.Add($this.MakeToken([TT]::PIPE, '|', $currentLine, $currentCol)) }
                '^' { $list.Add($this.MakeToken([TT]::CARET, '^', $currentLine, $currentCol)) }
                '~' { $list.Add($this.MakeToken([TT]::TILDE, '~', $currentLine, $currentCol)) }
                '!' { $list.Add($this.MakeToken([TT]::BANG, '!', $currentLine, $currentCol)) }
                default { throw "lexer error at L$($currentLine):$($currentCol): unexpected char '$c'" }
            }
            $this.Advance()
        }

        $list.Add($this.MakeToken([TT]::EOF, '', $this.Line, $this.Col))
        return $list.ToArray()
    }
}

class Parser {
    [Token[]]$Toks
    [int]$Pos = 0
    [System.Collections.Generic.List[string]]$Errors

    Parser([Token[]]$toks) {
        $this.Toks = $toks
        $this.Errors = [System.Collections.Generic.List[string]]::new()
    }

    [Token] Cur() { return $this.Toks[$this.Pos] }
    [Token] Peek([int]$n = 1) {
        $i = $this.Pos + $n
        if ($i -ge $this.Toks.Length) { return $this.Toks[$this.Toks.Length - 1] }
        return $this.Toks[$i]
    }
    [bool] Check([TT]$t) { return $this.Cur().Type -eq $t }
    [bool] CheckVal([string]$v) { return $this.Cur().Value -eq $v }

    [Token] Eat([TT]$t) {
        if ($this.Cur().Type -ne $t) {
            $msg = "L$($this.Cur().Line):$($this.Cur().Col): expected $t got $($this.Cur().Type) ('$($this.Cur().Value)')"
            $this.Errors.Add($msg)
            throw $msg
        }
        $tok = $this.Cur(); $this.Pos++; return $tok
    }

    [bool] TryEat([TT]$t) {
        if ($this.Cur().Type -eq $t) { $this.Pos++; return $true }
        return $false
    }

    [void] SkipSemi() { $this.TryEat([TT]::SEMI) | Out-Null }

    [hashtable] ParseType() {
        $types = [System.Collections.Generic.List[hashtable]]::new()
        $types.Add($this.ParseSingleType())
        while ($this.Check([TT]::PIPE)) {
            $this.Eat([TT]::PIPE)
            $types.Add($this.ParseSingleType())
        }
        if ($types.Count -eq 1) { return $types[0] }
        return @{ type = 'UnionType'; members = $types.ToArray() }
    }

    [hashtable] ParseSingleType() {
        $base = $null

        if ($this.Check([TT]::LBRACKET)) {
            $this.Eat([TT]::LBRACKET)
            $members = [System.Collections.Generic.List[hashtable]]::new()
            while (-not $this.Check([TT]::RBRACKET)) {
                $members.Add($this.ParseType())
                $this.TryEat([TT]::COMMA) | Out-Null
            }
            $this.Eat([TT]::RBRACKET)
            $base = @{ type = 'TupleType'; members = $members.ToArray() }
        } elseif ($this.Check([TT]::LPAREN)) {
            $saved = $this.Pos
            $savedErrorsCount = $this.Errors.Count
            try {
                $this.Eat([TT]::LPAREN)
                $params = $this.ParseFunctionTypeParams()
                $this.Eat([TT]::RPAREN)
                $this.Eat([TT]::ARROW)
                $ret = $this.ParseType()
                $base = @{ type = 'FunctionType'; params = $params; returnType = $ret }
            } catch {
                while ($this.Errors.Count -gt $savedErrorsCount) { $this.Errors.RemoveAt($this.Errors.Count - 1) }
                $this.Pos = $saved
                $this.Eat([TT]::LPAREN)
                $inner = $this.ParseType()
                $this.Eat([TT]::RPAREN)
                $base = $inner
            }
        } elseif ($this.Check([TT]::LBRACE)) {
            $base = $this.ParseObjectType()
        } elseif ($this.Check([TT]::TYPEOF)) {
            $this.Eat([TT]::TYPEOF)
            $name = $this.Eat([TT]::IDENT).Value
            $base = @{ type = 'TypeofType'; name = $name }
        } elseif ($this.CheckVal('keyof')) {
            $this.Pos++
            $inner = $this.ParseSingleType()
            $base = @{ type = 'KeyofType'; inner = $inner }
        } else {
            $name = $this.Cur().Value; $this.Pos++
            $base = @{ type = 'TypeReference'; name = $name }
            if ($this.Check([TT]::LT)) {
                $this.Eat([TT]::LT)
                $args = [System.Collections.Generic.List[hashtable]]::new()
                while (-not $this.Check([TT]::GT)) {
                    $args.Add($this.ParseType())
                    $this.TryEat([TT]::COMMA) | Out-Null
                }
                $this.Eat([TT]::GT)
                $base = @{ type = 'GenericType'; name = $name; args = $args.ToArray() }
            }
        }

        while ($this.Check([TT]::LBRACKET) -and $this.Peek(1).Type -eq [TT]::RBRACKET) {
            $this.Eat([TT]::LBRACKET); $this.Eat([TT]::RBRACKET)
            $base = @{ type = 'ArrayType'; elementType = $base }
        }

        while ($this.Check([TT]::AMP)) {
            $this.Eat([TT]::AMP)
            $right = $this.ParseSingleType()
            $base = @{ type = 'IntersectionType'; left = $base; right = $right }
        }

        return $base
    }

    [hashtable[]] ParseFunctionTypeParams() {
        $params = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RPAREN)) {
            $rest = $this.TryEat([TT]::ELLIPSIS)
            $pname = $this.Eat([TT]::IDENT).Value
            $optional = $this.TryEat([TT]::QUESTION)
            $ptype = $null
            if ($this.TryEat([TT]::COLON)) { $ptype = $this.ParseType() }
            $params.Add(@{ name = $pname; tsType = $ptype; optional = [bool]$optional; rest = [bool]$rest })
            $this.TryEat([TT]::COMMA) | Out-Null
        }
        return $params.ToArray()
    }

    [hashtable] ParseObjectType() {
        $this.Eat([TT]::LBRACE)
        $members = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RBRACE)) {
            $readonly = $this.TryEat([TT]::READONLY)
            $key = $this.Cur().Value; $this.Pos++
            $optional = $this.TryEat([TT]::QUESTION)
            $this.Eat([TT]::COLON)
            $vtype = $this.ParseType()
            $this.TryEat([TT]::SEMI) | Out-Null
            $this.TryEat([TT]::COMMA) | Out-Null
            $members.Add(@{ key = $key; valueType = $vtype; optional = [bool]$optional; readonly = [bool]$readonly })
        }
        $this.Eat([TT]::RBRACE)
        return @{ type = 'ObjectType'; members = $members.ToArray() }
    }

    [object[]] ParseProgram() {
        $nodes = [System.Collections.Generic.List[object]]::new()
        while (-not $this.Check([TT]::EOF)) {
            try {
                $s = $this.ParseStatement()
                if ($null -ne $s) { $nodes.Add($s) }
            } catch {
                $startPos = $this.Pos
                while (-not $this.Check([TT]::EOF) -and
                       $this.Cur().Type -notin @([TT]::SEMI, [TT]::RBRACE, [TT]::LET, [TT]::CONST, [TT]::VAR,
                                                  [TT]::FUNCTION, [TT]::CLASS, [TT]::INTERFACE, [TT]::TYPE,
                                                  [TT]::ENUM, [TT]::IMPORT, [TT]::EXPORT, [TT]::NAMESPACE)) {
                    $this.Pos++
                }
                $this.TryEat([TT]::SEMI) | Out-Null
                if ($this.Pos -eq $startPos -and -not $this.Check([TT]::EOF)) {
                    $this.Pos++
                }
            }
        }
        return $nodes.ToArray()
    }

    [hashtable] ParseStatement() {
        $decorators = @()
        while ($this.Check([TT]::AT)) { $decorators += $this.ParseDecorator() }

        if ($this.Check([TT]::EXPORT)) {
            return $this.ParseExport($decorators, @())
        }

        $modifiers = $this.ParseModifiers()

        switch ($this.Cur().Type) {
            ([TT]::LET) { return $this.ParseVarDecl('let', $decorators, $modifiers) }
            ([TT]::CONST) { return $this.ParseVarDecl('const', $decorators, $modifiers) }
            ([TT]::VAR) { return $this.ParseVarDecl('var', $decorators, $modifiers) }
            ([TT]::FUNCTION) { return $this.ParseFunctionDecl($decorators, $modifiers) }
            ([TT]::CLASS) { return $this.ParseClassDecl($decorators, $modifiers) }
            ([TT]::INTERFACE) { return $this.ParseInterfaceDecl($modifiers) }
            ([TT]::TYPE) { return $this.ParseTypeAlias($modifiers) }
            ([TT]::ENUM) { return $this.ParseEnumDecl($modifiers) }
            ([TT]::NAMESPACE) { return $this.ParseNamespace($modifiers) }
            ([TT]::IMPORT) { return $this.ParseImport() }
            ([TT]::EXPORT) { return $this.ParseExport($decorators, $modifiers) }
            ([TT]::RETURN) { return $this.ParseReturn() }
            ([TT]::IF) { return $this.ParseIf() }
            ([TT]::WHILE) { return $this.ParseWhile() }
            ([TT]::DO) { return $this.ParseDoWhile() }
            ([TT]::FOR) { return $this.ParseFor() }
            ([TT]::SWITCH) { return $this.ParseSwitch() }
            ([TT]::BREAK) { $this.Pos++; $this.SkipSemi(); return @{ type = 'BreakStatement' } }
            ([TT]::CONTINUE) { $this.Pos++; $this.SkipSemi(); return @{ type = 'ContinueStatement' } }
            ([TT]::THROW) { return $this.ParseThrow() }
            ([TT]::TRY) { return $this.ParseTryCatch() }
            ([TT]::LBRACE) { return $this.ParseBlock() }
            ([TT]::SEMI) { $this.Pos++; return $null }
            ([TT]::DEBUGGER) { $this.Pos++; $this.SkipSemi(); return @{ type = 'DebuggerStatement' } }
            default { return $this.ParseExpressionStatement() }
        }
        return $null
    }

    [string[]] ParseModifiers() {
        $mods = [System.Collections.Generic.List[string]]::new()
        $modSet = @([TT]::ASYNC, [TT]::STATIC, [TT]::READONLY,
                    [TT]::PUBLIC, [TT]::PRIVATE, [TT]::PROTECTED, [TT]::ABSTRACT, [TT]::DECLARE)
        while ($this.Cur().Type -in $modSet) { $mods.Add($this.Cur().Value); $this.Pos++ }
        return $mods.ToArray()
    }

    [hashtable] ParseNamespace($modifiers) {
        $this.Eat([TT]::NAMESPACE)
        $name = $this.Eat([TT]::IDENT).Value
        $body = $this.ParseBlock()
        return @{ type = 'NamespaceDeclaration'; name = $name; body = $body; modifiers = $modifiers }
    }

    [hashtable] ParseDecorator() {
        $this.Eat([TT]::AT)
        $name = $this.Eat([TT]::IDENT).Value
        $args = @()
        if ($this.Check([TT]::LPAREN)) {
            $this.Eat([TT]::LPAREN); $args = $this.ParseArgList(); $this.Eat([TT]::RPAREN)
        }
        return @{ type = 'Decorator'; name = $name; args = $args }
    }

    [hashtable] ParseVarDecl([string]$kind, $decorators, $modifiers) {
        $this.Pos++
        $declarators = [System.Collections.Generic.List[hashtable]]::new()
        do {
            if ($this.Check([TT]::LBRACE)) {
                $pattern = $this.ParseObjectDestructuring()
                $tsType = $null; if ($this.TryEat([TT]::COLON)) { $tsType = $this.ParseType() }
                $init = $null; if ($this.TryEat([TT]::EQUALS)) { $init = $this.ParseExpression() }
                $declarators.Add(@{ type = 'ObjectDestructuring'; pattern = $pattern; tsType = $tsType; initializer = $init })
            } elseif ($this.Check([TT]::LBRACKET)) {
                $pattern = $this.ParseArrayDestructuring()
                $tsType = $null; if ($this.TryEat([TT]::COLON)) { $tsType = $this.ParseType() }
                $init = $null; if ($this.TryEat([TT]::EQUALS)) { $init = $this.ParseExpression() }
                $declarators.Add(@{ type = 'ArrayDestructuring'; pattern = $pattern; tsType = $tsType; initializer = $init })
            } else {
                $name = $this.Eat([TT]::IDENT).Value
                $tsType = $null; $optional = $false
                if ($this.TryEat([TT]::QUESTION)) { $optional = $true }
                if ($this.TryEat([TT]::COLON)) { $tsType = $this.ParseType() }
                $init = $null; if ($this.TryEat([TT]::EQUALS)) { $init = $this.ParseExpression() }
                $declarators.Add(@{ type = 'VariableDeclarator'; name = $name; tsType = $tsType; initializer = $init; optional = $optional })
            }
        } while ($this.TryEat([TT]::COMMA))
        $this.SkipSemi()
        return @{ type = 'VariableDeclaration'; kind = $kind; declarators = $declarators.ToArray(); decorators = $decorators; modifiers = $modifiers }
    }

    [hashtable[]] ParseObjectDestructuring() {
        $this.Eat([TT]::LBRACE)
        $props = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RBRACE)) {
            $rest = $this.TryEat([TT]::ELLIPSIS)
            $key = $this.Cur().Value; $this.Pos++
            $alias = $key
            if ($this.TryEat([TT]::COLON)) { $alias = $this.Eat([TT]::IDENT).Value }
            $default = $null; if ($this.TryEat([TT]::EQUALS)) { $default = $this.ParseExpression() }
            $props.Add(@{ key = $key; alias = $alias; default = $default; rest = [bool]$rest })
            $this.TryEat([TT]::COMMA) | Out-Null
        }
        $this.Eat([TT]::RBRACE)
        return $props.ToArray()
    }

    [hashtable[]] ParseArrayDestructuring() {
        $this.Eat([TT]::LBRACKET)
        $elems = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RBRACKET)) {
            if ($this.Check([TT]::COMMA)) { $elems.Add($null); $this.Pos++; continue }
            $rest = $this.TryEat([TT]::ELLIPSIS)
            $name = $this.Eat([TT]::IDENT).Value
            $default = $null; if ($this.TryEat([TT]::EQUALS)) { $default = $this.ParseExpression() }
            $elems.Add(@{ name = $name; default = $default; rest = [bool]$rest })
            $this.TryEat([TT]::COMMA) | Out-Null
        }
        $this.Eat([TT]::RBRACKET)
        return $elems.ToArray()
    }

    [hashtable] ParseFunctionDecl($decorators, $modifiers) {
        $this.Eat([TT]::FUNCTION)
        $isGen = $this.TryEat([TT]::STAR)
        $name = $null; if ($this.Check([TT]::IDENT)) { $name = $this.Eat([TT]::IDENT).Value }
        $typeParams = $this.ParseTypeParams()
        $this.Eat([TT]::LPAREN); $params = $this.ParseParams(); $this.Eat([TT]::RPAREN)
        $retType = $null; if ($this.TryEat([TT]::COLON)) { $retType = $this.ParseType() }
        $body = $null
        if ($this.Check([TT]::LBRACE)) { $body = $this.ParseBlock() } else { $this.SkipSemi() }
        return @{
            type = 'FunctionDeclaration'; name = $name; typeParams = $typeParams
            params = $params; returnType = $retType; body = $body
            generator = [bool]$isGen; decorators = $decorators; modifiers = $modifiers
        }
    }

    [hashtable[]] ParseTypeParams() {
        $tps = @()
        if ($this.Check([TT]::LT)) {
            $this.Eat([TT]::LT)
            $list = [System.Collections.Generic.List[hashtable]]::new()
            while (-not $this.Check([TT]::GT)) {
                $n = $this.Eat([TT]::IDENT).Value
                $constraint = $null; if ($this.CheckVal('extends')) { $this.Pos++; $constraint = $this.ParseType() }
                $default = $null; if ($this.TryEat([TT]::EQUALS)) { $default = $this.ParseType() }
                $list.Add(@{ name = $n; constraint = $constraint; default = $default })
                $this.TryEat([TT]::COMMA) | Out-Null
            }
            $this.Eat([TT]::GT); $tps = $list.ToArray()
        }
        return $tps
    }

    [hashtable[]] ParseParams() {
        $params = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RPAREN)) {
            $decorators = @()
            while ($this.Check([TT]::AT)) { $decorators += $this.ParseDecorator() }
            $modifiers = $this.ParseModifiers()
            $rest = $this.TryEat([TT]::ELLIPSIS)
            if ($this.Check([TT]::LBRACE)) {
                $pat = $this.ParseObjectDestructuring()
                $tsType = $null; if ($this.TryEat([TT]::COLON)) { $tsType = $this.ParseType() }
                $default = $null; if ($this.TryEat([TT]::EQUALS)) { $default = $this.ParseExpression() }
                $params.Add(@{ type = 'DestructuredParam'; pattern = $pat; tsType = $tsType; default = $default })
            } else {
                $name = $this.Eat([TT]::IDENT).Value
                $opt = $this.TryEat([TT]::QUESTION)
                $tsType = $null; if ($this.TryEat([TT]::COLON)) { $tsType = $this.ParseType() }
                $default = $null; if ($this.TryEat([TT]::EQUALS)) { $default = $this.ParseExpression() }
                $params.Add(@{
                    type = 'Parameter'; name = $name; tsType = $tsType
                    optional = [bool]$opt; rest = [bool]$rest; default = $default
                    decorators = $decorators; modifiers = $modifiers
                })
            }
            $this.TryEat([TT]::COMMA) | Out-Null
        }
        return $params.ToArray()
    }

    [hashtable] ParseClassDecl($decorators, $modifiers) {
        $this.Eat([TT]::CLASS)
        $name = $null; if ($this.Check([TT]::IDENT)) { $name = $this.Eat([TT]::IDENT).Value }
        $typeParams = $this.ParseTypeParams()
        $superClass = $null
        if ($this.Check([TT]::EXTENDS)) { $this.Eat([TT]::EXTENDS); $superClass = $this.ParseType() }
        $implems = @()
        if ($this.Check([TT]::IMPLEMENTS)) {
            $this.Eat([TT]::IMPLEMENTS)
            $ilist = [System.Collections.Generic.List[hashtable]]::new()
            do { $ilist.Add($this.ParseType()); $this.TryEat([TT]::COMMA) | Out-Null } while ($this.Check([TT]::IDENT))
            $implems = $ilist.ToArray()
        }
        $this.Eat([TT]::LBRACE)
        $members = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RBRACE)) { $members.Add($this.ParseClassMember()) }
        $this.Eat([TT]::RBRACE)
        return @{
            type = 'ClassDeclaration'; name = $name; typeParams = $typeParams
            superClass = $superClass; implements = $implems; members = $members.ToArray()
            decorators = $decorators; modifiers = $modifiers
        }
    }

    [hashtable] ParseClassMember() {
        $decorators = @()
        while ($this.Check([TT]::AT)) { $decorators += $this.ParseDecorator() }
        $modifiers = $this.ParseModifiers()

        if ($this.Check([TT]::LBRACKET)) {
            $this.Eat([TT]::LBRACKET)
            $key = $this.Eat([TT]::IDENT).Value
            $this.Eat([TT]::COLON); $keyType = $this.ParseType(); $this.Eat([TT]::RBRACKET)
            $this.Eat([TT]::COLON); $valType = $this.ParseType(); $this.SkipSemi()
            return @{ type = 'IndexSignature'; key = $key; keyType = $keyType; valueType = $valType; decorators = $decorators; modifiers = $modifiers }
        }

        if ($this.CheckVal('constructor')) {
            $this.Pos++
            $this.Eat([TT]::LPAREN); $params = $this.ParseParams(); $this.Eat([TT]::RPAREN)
            $retType = $null; if ($this.TryEat([TT]::COLON)) { $retType = $this.ParseType() }
            $body = $null
            if ($this.Check([TT]::LBRACE)) { $body = $this.ParseBlock() } else { $this.SkipSemi() }
            return @{ type = 'Constructor'; params = $params; returnType = $retType; body = $body; decorators = $decorators; modifiers = $modifiers }
        }

        if ($this.Cur().Value -in @('get','set') -and $this.Peek(1).Type -eq [TT]::IDENT) {
            $kind = $this.Cur().Value; $this.Pos++
            $name = $this.Cur().Value; $this.Pos++
            $this.Eat([TT]::LPAREN); $params = $this.ParseParams(); $this.Eat([TT]::RPAREN)
            $retType = $null; if ($this.TryEat([TT]::COLON)) { $retType = $this.ParseType() }
            $body = $null
            if ($this.Check([TT]::LBRACE)) { $body = $this.ParseBlock() } else { $this.SkipSemi() }
            return @{ type = 'Accessor'; kind = $kind; name = $name; params = $params; returnType = $retType; body = $body; decorators = $decorators; modifiers = $modifiers }
        }

        $isGen = $this.TryEat([TT]::STAR)
        $name = $this.Cur().Value; $this.Pos++
        $opt = $this.TryEat([TT]::QUESTION)

        if ($this.Check([TT]::LPAREN) -or $this.Check([TT]::LT)) {
            $typeParams = $this.ParseTypeParams()
            $this.Eat([TT]::LPAREN); $params = $this.ParseParams(); $this.Eat([TT]::RPAREN)
            $retType = $null; if ($this.TryEat([TT]::COLON)) { $retType = $this.ParseType() }
            $body = $null
            if ($this.Check([TT]::LBRACE)) { $body = $this.ParseBlock() } else { $this.SkipSemi() }
            return @{ type = 'MethodDefinition'; name = $name; typeParams = $typeParams; params = $params; returnType = $retType; body = $body; generator = [bool]$isGen; optional = [bool]$opt; decorators = $decorators; modifiers = $modifiers }
        }

        $tsType = $null; if ($this.TryEat([TT]::COLON)) { $tsType = $this.ParseType() }
        $init = $null; if ($this.TryEat([TT]::EQUALS)) { $init = $this.ParseExpression() }
        $this.SkipSemi()
        return @{ type = 'ClassField'; name = $name; tsType = $tsType; initializer = $init; optional = [bool]$opt; decorators = $decorators; modifiers = $modifiers }
    }

    [hashtable] ParseInterfaceDecl($modifiers) {
        $this.Eat([TT]::INTERFACE)
        $name = $this.Eat([TT]::IDENT).Value
        $typeParams = $this.ParseTypeParams()
        $extends = @()
        if ($this.CheckVal('extends')) {
            $this.Pos++
            $elist = [System.Collections.Generic.List[hashtable]]::new()
            do { $elist.Add($this.ParseType()); $this.TryEat([TT]::COMMA) | Out-Null } while ($this.Check([TT]::IDENT))
            $extends = $elist.ToArray()
        }
        $body = $this.ParseObjectType(); $this.SkipSemi()
        return @{ type = 'InterfaceDeclaration'; name = $name; typeParams = $typeParams; extends = $extends; body = $body; modifiers = $modifiers }
    }

    [hashtable] ParseTypeAlias($modifiers) {
        $this.Eat([TT]::TYPE)
        $name = $this.Eat([TT]::IDENT).Value
        $typeParams = $this.ParseTypeParams()
        $this.Eat([TT]::EQUALS)
        $value = $this.ParseType(); $this.SkipSemi()
        return @{ type = 'TypeAlias'; name = $name; typeParams = $typeParams; value = $value; modifiers = $modifiers }
    }

    [hashtable] ParseEnumDecl($modifiers) {
        $this.Eat([TT]::ENUM)
        $name = $this.Eat([TT]::IDENT).Value
        $this.Eat([TT]::LBRACE)
        $members = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RBRACE)) {
            $mname = $this.Cur().Value; $this.Pos++
            $value = $null; if ($this.TryEat([TT]::EQUALS)) { $value = $this.ParseExpression() }
            $members.Add(@{ name = $mname; value = $value })
            $this.TryEat([TT]::COMMA) | Out-Null
        }
        $this.Eat([TT]::RBRACE)
        return @{ type = 'EnumDeclaration'; name = $name; members = $members.ToArray(); modifiers = $modifiers }
    }

    [hashtable] ParseImport() {
        $this.Eat([TT]::IMPORT)
        $importType = $this.CheckVal('type') -and $this.Peek(1).Type -ne [TT]::FROM
        if ($importType) { $this.Pos++ }

        if ($this.Check([TT]::STRING)) {
            $src = $this.Eat([TT]::STRING).Value; $this.SkipSemi()
            return @{ type = 'ImportDeclaration'; source = $src; specifiers = @(); importType = $importType }
        }

        $specifiers = [System.Collections.Generic.List[hashtable]]::new()

        if ($this.Check([TT]::IDENT)) {
            $def = $this.Eat([TT]::IDENT).Value
            $specifiers.Add(@{ kind = 'default'; name = $def })
            $this.TryEat([TT]::COMMA) | Out-Null
        }

        if ($this.Check([TT]::STAR)) {
            $this.Eat([TT]::STAR)
            $this.CheckVal('as') | Out-Null; $this.Pos++
            $ns = $this.Eat([TT]::IDENT).Value
            $specifiers.Add(@{ kind = 'namespace'; name = $ns })
        }

        if ($this.Check([TT]::LBRACE)) {
            $this.Eat([TT]::LBRACE)
            while (-not $this.Check([TT]::RBRACE)) {
                $orig = $this.Cur().Value; $this.Pos++
                $alias = $orig
                if ($this.CheckVal('as')) { $this.Pos++; $alias = $this.Eat([TT]::IDENT).Value }
                $specifiers.Add(@{ kind = 'named'; orig = $orig; name = $alias })
                $this.TryEat([TT]::COMMA) | Out-Null
            }
            $this.Eat([TT]::RBRACE)
        }

        $src = ''
        if ($this.CheckVal('from')) { $this.Pos++; $src = $this.Eat([TT]::STRING).Value }
        $this.SkipSemi()
        return @{ type = 'ImportDeclaration'; source = $src; specifiers = $specifiers.ToArray(); importType = $importType }
    }

    [hashtable] ParseExport($decorators, $modifiers) {
        $this.Eat([TT]::EXPORT)

        if ($this.Check([TT]::DEFAULT)) {
            $this.Eat([TT]::DEFAULT)
            if ($this.Check([TT]::FUNCTION)) { return @{ type = 'ExportDefault'; declaration = $this.ParseFunctionDecl($decorators, $modifiers) } }
            if ($this.Check([TT]::CLASS)) { return @{ type = 'ExportDefault'; declaration = $this.ParseClassDecl($decorators, $modifiers) } }
            $expr = $this.ParseExpression(); $this.SkipSemi()
            return @{ type = 'ExportDefault'; declaration = $expr }
        }

        if ($this.Check([TT]::LBRACE)) {
            $this.Eat([TT]::LBRACE)
            $specs = [System.Collections.Generic.List[hashtable]]::new()
            while (-not $this.Check([TT]::RBRACE)) {
                $orig = $this.Cur().Value; $this.Pos++
                $alias = $orig
                if ($this.CheckVal('as')) { $this.Pos++; $alias = $this.Cur().Value; $this.Pos++ }
                $specs.Add(@{ orig = $orig; alias = $alias })
                $this.TryEat([TT]::COMMA) | Out-Null
            }
            $this.Eat([TT]::RBRACE)
            $src = $null; if ($this.CheckVal('from')) { $this.Pos++; $src = $this.Eat([TT]::STRING).Value }
            $this.SkipSemi()
            return @{ type = 'ExportNamed'; specifiers = $specs.ToArray(); source = $src }
        }

        if ($this.Check([TT]::STAR)) {
            $this.Eat([TT]::STAR)
            $alias = $null; if ($this.CheckVal('as')) { $this.Pos++; $alias = $this.Eat([TT]::IDENT).Value }
            $src = $null; if ($this.CheckVal('from')) { $this.Pos++; $src = $this.Eat([TT]::STRING).Value }
            $this.SkipSemi()
            return @{ type = 'ExportAll'; alias = $alias; source = $src }
        }

        return @{ type = 'ExportDeclaration'; declaration = $this.ParseStatement() }
    }

    [hashtable] ParseReturn() {
        $this.Eat([TT]::RETURN)
        $value = $null
        if (-not $this.Check([TT]::SEMI) -and -not $this.Check([TT]::RBRACE) -and -not $this.Check([TT]::EOF)) {
            $value = $this.ParseExpression()
        }
        $this.SkipSemi()
        return @{ type = 'ReturnStatement'; value = $value }
    }

    [hashtable] ParseThrow() {
        $this.Eat([TT]::THROW)
        $value = $this.ParseExpression(); $this.SkipSemi()
        return @{ type = 'ThrowStatement'; value = $value }
    }

    [hashtable] ParseIf() {
        $this.Eat([TT]::IF)
        $this.Eat([TT]::LPAREN); $cond = $this.ParseExpression(); $this.Eat([TT]::RPAREN)
        $then = $this.ParseStatement()
        $alt = $null
        if ($this.Check([TT]::ELSE)) { $this.Eat([TT]::ELSE); $alt = $this.ParseStatement() }
        return @{ type = 'IfStatement'; condition = $cond; then = $then; else = $alt }
    }

    [hashtable] ParseWhile() {
        $this.Eat([TT]::WHILE)
        $this.Eat([TT]::LPAREN); $cond = $this.ParseExpression(); $this.Eat([TT]::RPAREN)
        return @{ type = 'WhileStatement'; condition = $cond; body = $this.ParseStatement() }
    }

    [hashtable] ParseDoWhile() {
        $this.Eat([TT]::DO); $body = $this.ParseStatement()
        $this.Eat([TT]::WHILE); $this.Eat([TT]::LPAREN)
        $cond = $this.ParseExpression(); $this.Eat([TT]::RPAREN); $this.SkipSemi()
        return @{ type = 'DoWhileStatement'; body = $body; condition = $cond }
    }

    [hashtable] ParseFor() {
        $this.Eat([TT]::FOR); $this.Eat([TT]::LPAREN)
        $isAwait = $false
        if ($this.CheckVal('await')) { $this.Pos++; $isAwait = $true }

        if ($this.Cur().Type -in @([TT]::LET, [TT]::CONST, [TT]::VAR)) {
            $kind = $this.Cur().Value; $this.Pos++
            $name = $this.Cur().Value; $this.Pos++
            if ($this.Check([TT]::OF)) {
                $this.Eat([TT]::OF); $iterable = $this.ParseExpression(); $this.Eat([TT]::RPAREN)
                return @{ type = 'ForOfStatement'; kind = $kind; name = $name; iterable = $iterable; body = $this.ParseStatement(); await = $isAwait }
            }
            if ($this.Check([TT]::IN)) {
                $this.Eat([TT]::IN); $iterable = $this.ParseExpression(); $this.Eat([TT]::RPAREN)
                return @{ type = 'ForInStatement'; kind = $kind; name = $name; iterable = $iterable; body = $this.ParseStatement() }
            }
            $this.Pos -= 2
        }

        $init = $null
        if (-not $this.Check([TT]::SEMI)) { $init = $this.ParseStatement() } else { $this.Eat([TT]::SEMI) }
        $cond = $null; if (-not $this.Check([TT]::SEMI)) { $cond = $this.ParseExpression() }
        $this.Eat([TT]::SEMI)
        $update = $null; if (-not $this.Check([TT]::RPAREN)) { $update = $this.ParseExpression() }
        $this.Eat([TT]::RPAREN)
        return @{ type = 'ForStatement'; init = $init; condition = $cond; update = $update; body = $this.ParseStatement() }
    }

    [hashtable] ParseSwitch() {
        $this.Eat([TT]::SWITCH); $this.Eat([TT]::LPAREN)
        $disc = $this.ParseExpression(); $this.Eat([TT]::RPAREN); $this.Eat([TT]::LBRACE)
        $cases = [System.Collections.Generic.List[hashtable]]::new()
        while (-not $this.Check([TT]::RBRACE)) {
            if ($this.Check([TT]::CASE)) {
                $this.Eat([TT]::CASE); $test = $this.ParseExpression(); $this.Eat([TT]::COLON)
                $stmts = [System.Collections.Generic.List[object]]::new()
                while (-not $this.Check([TT]::CASE) -and -not $this.CheckVal('default') -and -not $this.Check([TT]::RBRACE)) {
                    $stmts.Add($this.ParseStatement())
                }
                $cases.Add(@{ type = 'SwitchCase'; test = $test; body = $stmts.ToArray() })
            } elseif ($this.Check([TT]::DEFAULT)) {
                $this.Eat([TT]::DEFAULT); $this.Eat([TT]::COLON)
                $stmts = [System.Collections.Generic.List[object]]::new()
                while (-not $this.Check([TT]::CASE) -and -not $this.CheckVal('default') -and -not $this.Check([TT]::RBRACE)) {
                    $stmts.Add($this.ParseStatement())
                }
                $cases.Add(@{ type = 'DefaultCase'; body = $stmts.ToArray() })
            } else { break }
        }
        $this.Eat([TT]::RBRACE)
        return @{ type = 'SwitchStatement'; discriminant = $disc; cases = $cases.ToArray() }
    }

    [hashtable] ParseTryCatch() {
        $this.Eat([TT]::TRY); $tryBlock = $this.ParseBlock()
        $catch = $null
        if ($this.Check([TT]::CATCH)) {
            $this.Eat([TT]::CATCH)
            $param = $null; $paramType = $null
            if ($this.TryEat([TT]::LPAREN)) {
                $param = $this.Eat([TT]::IDENT).Value
                if ($this.TryEat([TT]::COLON)) { $paramType = $this.ParseType() }
                $this.Eat([TT]::RPAREN)
            }
            $catch = @{ param = $param; paramType = $paramType; body = $this.ParseBlock() }
        }
        $finally = $null
        if ($this.Check([TT]::FINALLY)) { $this.Eat([TT]::FINALLY); $finally = $this.ParseBlock() }
        return @{ type = 'TryCatchStatement'; try = $tryBlock; catch = $catch; finally = $finally }
    }

    [hashtable] ParseBlock() {
        $this.Eat([TT]::LBRACE)
        $stmts = [System.Collections.Generic.List[object]]::new()
        while (-not $this.Check([TT]::RBRACE) -and -not $this.Check([TT]::EOF)) {
            $s = $this.ParseStatement()
            if ($null -ne $s) { $stmts.Add($s) }
        }
        $this.Eat([TT]::RBRACE)
        return @{ type = 'BlockStatement'; body = $stmts.ToArray() }
    }

    [hashtable] ParseExpressionStatement() {
        $expr = $this.ParseExpression(); $this.SkipSemi()
        return @{ type = 'ExpressionStatement'; expression = $expr }
    }

    [hashtable] ParseExpression() { return $this.ParseAssignment() }

    [hashtable] ParseAssignment() {
        $left = $this.ParseTernary()
        $assignOps = @(
            [TT]::EQUALS, [TT]::PLUS_EQ, [TT]::MINUS_EQ, [TT]::STAR_EQ, [TT]::SLASH_EQ,
            [TT]::MOD_EQ, [TT]::AMP_EQ, [TT]::PIPE_EQ, [TT]::CARET_EQ,
            [TT]::LSHIFT_EQ, [TT]::RSHIFT_EQ, [TT]::URSHIFT_EQ,
            [TT]::STAR_STAR_EQ, [TT]::AND_EQ, [TT]::OR_EQ, [TT]::NULLISH_EQ
        )
        if ($this.Cur().Type -in $assignOps) {
            $op = $this.Cur().Value; $this.Pos++
            return @{ type = 'AssignmentExpression'; operator = $op; left = $left; right = $this.ParseAssignment() }
        }
        return $left
    }

    [hashtable] ParseTernary() {
        $cond = $this.ParseNullish()
        if ($this.Check([TT]::QUESTION)) {
            $this.Eat([TT]::QUESTION)
            $then = $this.ParseAssignment(); $this.Eat([TT]::COLON)
            return @{ type = 'TernaryExpression'; condition = $cond; then = $then; else = $this.ParseAssignment() }
        }
        return $cond
    }

    [hashtable] ParseNullish() {
        $left = $this.ParseOr()
        while ($this.Check([TT]::NULLISH)) {
            $this.Eat([TT]::NULLISH); $right = $this.ParseOr()
            $left = @{ type = 'BinaryExpression'; operator = '??'; left = $left; right = $right }
        }
        return $left
    }

    [hashtable] ParseOr() {
        $left = $this.ParseAnd()
        while ($this.Check([TT]::PIPE_PIPE)) {
            $this.Eat([TT]::PIPE_PIPE); $right = $this.ParseAnd()
            $left = @{ type = 'LogicalExpression'; operator = '||'; left = $left; right = $right }
        }
        return $left
    }

    [hashtable] ParseAnd() {
        $left = $this.ParseBitwiseOr()
        while ($this.Check([TT]::AMP_AMP)) {
            $this.Eat([TT]::AMP_AMP); $right = $this.ParseBitwiseOr()
            $left = @{ type = 'LogicalExpression'; operator = '&&'; left = $left; right = $right }
        }
        return $left
    }

    [hashtable] ParseBitwiseOr() {
        $left = $this.ParseBitwiseXor()
        while ($this.Check([TT]::PIPE)) {
            $this.Eat([TT]::PIPE); $left = @{ type = 'BinaryExpression'; operator = '|'; left = $left; right = $this.ParseBitwiseXor() }
        }
        return $left
    }

    [hashtable] ParseBitwiseXor() {
        $left = $this.ParseBitwiseAnd()
        while ($this.Check([TT]::CARET)) {
            $this.Eat([TT]::CARET); $left = @{ type = 'BinaryExpression'; operator = '^'; left = $left; right = $this.ParseBitwiseAnd() }
        }
        return $left
    }

    [hashtable] ParseBitwiseAnd() {
        $left = $this.ParseEquality()
        while ($this.Check([TT]::AMP)) {
            $this.Eat([TT]::AMP); $left = @{ type = 'BinaryExpression'; operator = '&'; left = $left; right = $this.ParseEquality() }
        }
        return $left
    }

    [hashtable] ParseEquality() {
        $left = $this.ParseRelational()
        while ($this.Cur().Type -in @([TT]::EQ_EQ, [TT]::BANG_EQ, [TT]::EQ_EQ_EQ, [TT]::BANG_EQ_EQ)) {
            $op = $this.Cur().Value; $this.Pos++
            $left = @{ type = 'BinaryExpression'; operator = $op; left = $left; right = $this.ParseRelational() }
        }
        return $left
    }

    [hashtable] ParseRelational() {
        $left = $this.ParseShift()
        while ($this.Cur().Type -in @([TT]::LT, [TT]::GT, [TT]::LT_EQ, [TT]::GT_EQ, [TT]::INSTANCEOF, [TT]::IN)) {
            $op = $this.Cur().Value; $this.Pos++
            $left = @{ type = 'BinaryExpression'; operator = $op; left = $left; right = $this.ParseShift() }
        }
        return $left
    }

    [hashtable] ParseShift() {
        $left = $this.ParseAdditive()
        while ($this.Cur().Type -in @([TT]::LSHIFT, [TT]::RSHIFT, [TT]::URSHIFT)) {
            $op = $this.Cur().Value; $this.Pos++
            $left = @{ type = 'BinaryExpression'; operator = $op; left = $left; right = $this.ParseAdditive() }
        }
        return $left
    }

    [hashtable] ParseAdditive() {
        $left = $this.ParseMultiplicative()
        while ($this.Cur().Type -in @([TT]::PLUS, [TT]::MINUS)) {
            $op = $this.Cur().Value; $this.Pos++
            $left = @{ type = 'BinaryExpression'; operator = $op; left = $left; right = $this.ParseMultiplicative() }
        }
        return $left
    }

    [hashtable] ParseMultiplicative() {
        $left = $this.ParseExponentiation()
        while ($this.Cur().Type -in @([TT]::STAR, [TT]::SLASH, [TT]::MOD)) {
            $op = $this.Cur().Value; $this.Pos++
            $left = @{ type = 'BinaryExpression'; operator = $op; left = $left; right = $this.ParseExponentiation() }
        }
        return $left
    }

    [hashtable] ParseExponentiation() {
        $left = $this.ParseUnary()
        if ($this.Check([TT]::STAR_STAR)) {
            $this.Eat([TT]::STAR_STAR)
            return @{ type = 'BinaryExpression'; operator = '**'; left = $left; right = $this.ParseExponentiation() }
        }
        return $left
    }

    [hashtable] ParseUnary() {
        if ($this.Cur().Type -in @([TT]::PLUS_PLUS, [TT]::MINUS_MINUS)) {
            $op = $this.Cur().Value; $this.Pos++
            return @{ type = 'UpdateExpression'; operator = $op; prefix = $true; operand = $this.ParseUnary() }
        }
        if ($this.Cur().Type -in @([TT]::PLUS, [TT]::MINUS, [TT]::BANG, [TT]::TILDE)) {
            $op = $this.Cur().Value; $this.Pos++
            return @{ type = 'UnaryExpression'; operator = $op; operand = $this.ParseUnary() }
        }
        if ($this.Check([TT]::TYPEOF)) { $this.Eat([TT]::TYPEOF); return @{ type = 'UnaryExpression'; operator = 'typeof'; operand = $this.ParseUnary() } }
        if ($this.Check([TT]::VOID)) { $this.Eat([TT]::VOID); return @{ type = 'UnaryExpression'; operator = 'void'; operand = $this.ParseUnary() } }
        if ($this.Check([TT]::DELETE)) { $this.Eat([TT]::DELETE); return @{ type = 'UnaryExpression'; operator = 'delete'; operand = $this.ParseUnary() } }
        if ($this.Check([TT]::AWAIT)) { $this.Eat([TT]::AWAIT); return @{ type = 'AwaitExpression'; operand = $this.ParseUnary() } }
        if ($this.Check([TT]::YIELD)) {
            $this.Eat([TT]::YIELD)
            $delegate = $this.TryEat([TT]::STAR)
            $operand = $null
            if (-not $this.Check([TT]::SEMI) -and -not $this.Check([TT]::RBRACE)) { $operand = $this.ParseExpression() }
            return @{ type = 'YieldExpression'; delegate = [bool]$delegate; operand = $operand }
        }
        return $this.ParsePostfix()
    }

    [hashtable] ParsePostfix() {
        $expr = $this.ParseCallMember()
        if ($this.Cur().Type -in @([TT]::PLUS_PLUS, [TT]::MINUS_MINUS)) {
            $op = $this.Cur().Value; $this.Pos++
            return @{ type = 'UpdateExpression'; operator = $op; prefix = $false; operand = $expr }
        }
        if ($this.Check([TT]::AS)) {
            $this.Eat([TT]::AS)
            return @{ type = 'AsExpression'; expression = $expr; tsType = $this.ParseType() }
        }
        return $expr
    }

    [hashtable] ParseCallMember() {
        $expr = $this.ParsePrimary()
        while ($true) {
            if ($this.Check([TT]::DOT) -or $this.Check([TT]::OPT_CHAIN)) {
                $optional = $this.Check([TT]::OPT_CHAIN); $this.Pos++
                $prop = $this.Cur().Value; $this.Pos++
                $expr = @{ type = 'MemberExpression'; object = $expr; property = $prop; computed = $false; optional = $optional }
                continue
            }
            if ($this.Check([TT]::LBRACKET)) {
                $this.Eat([TT]::LBRACKET); $index = $this.ParseExpression(); $this.Eat([TT]::RBRACKET)
                $expr = @{ type = 'MemberExpression'; object = $expr; property = $index; computed = $true; optional = $false }
                continue
            }
            if ($this.Check([TT]::LPAREN)) {
                $this.Eat([TT]::LPAREN); $args = $this.ParseArgList(); $this.Eat([TT]::RPAREN)
                $expr = @{ type = 'CallExpression'; callee = $expr; args = $args }
                continue
            }
            if ($this.Check([TT]::LT) -and $expr.type -eq 'Identifier') {
                $saved = $this.Pos
                $savedErrorsCount = $this.Errors.Count
                try {
                    $this.Eat([TT]::LT)
                    $targs = [System.Collections.Generic.List[hashtable]]::new()
                    $targs.Add($this.ParseType())
                    while ($this.TryEat([TT]::COMMA)) { $targs.Add($this.ParseType()) }
                    $this.Eat([TT]::GT)
                    if ($this.Check([TT]::LPAREN)) {
                        $this.Eat([TT]::LPAREN); $args = $this.ParseArgList(); $this.Eat([TT]::RPAREN)
                        $expr = @{ type = 'GenericCallExpression'; callee = $expr; typeArgs = $targs.ToArray(); args = $args }
                        continue
                    } else { $this.Pos = $saved }
                } catch {
                    while ($this.Errors.Count -gt $savedErrorsCount) { $this.Errors.RemoveAt($this.Errors.Count - 1) }
                    $this.Pos = $saved 
                }
            }
            break
        }
        return $expr
    }

    [object[]] ParseArgList() {
        $args = [System.Collections.Generic.List[object]]::new()
        while (-not $this.Check([TT]::RPAREN)) {
            if ($this.Check([TT]::ELLIPSIS)) {
                $this.Eat([TT]::ELLIPSIS)
                $args.Add(@{ type = 'SpreadElement'; argument = $this.ParseExpression() })
            } else {
                $args.Add($this.ParseAssignment())
            }
            $this.TryEat([TT]::COMMA) | Out-Null
        }
        return $args.ToArray()
    }

    [hashtable] ParsePrimary() {
        $t = $this.Cur()
        switch ($t.Type) {
            ([TT]::NUMBER) { $this.Pos++; return @{ type = 'Literal'; kind = 'number'; value = $t.Value } }
            ([TT]::STRING) { $this.Pos++; return @{ type = 'Literal'; kind = 'string'; value = $t.Value } }
            ([TT]::TEMPLATE_STRING){ $this.Pos++; return @{ type = 'TemplateLiteral'; value = $t.Value } }
            ([TT]::BOOL) { $this.Pos++; return @{ type = 'Literal'; kind = 'boolean'; value = $t.Value } }
            ([TT]::NULL) { $this.Pos++; return @{ type = 'Literal'; kind = 'null'; value = 'null' } }
            ([TT]::UNDEFINED_KW) { $this.Pos++; return @{ type = 'Literal'; kind = 'undefined'; value = 'undefined' } }
            ([TT]::IDENT) { $this.Pos++; return @{ type = 'Identifier'; name = $t.Value } }

            ([TT]::LPAREN) {
                $saved = $this.Pos
                $savedErrorsCount = $this.Errors.Count
                try { return $this.ParseArrowOrParen() } catch {
                    while ($this.Errors.Count -gt $savedErrorsCount) { $this.Errors.RemoveAt($this.Errors.Count - 1) }
                    $this.Pos = $saved
                    $this.Eat([TT]::LPAREN); $inner = $this.ParseExpression(); $this.Eat([TT]::RPAREN)
                    return $inner
                }
            }

            ([TT]::LBRACKET) {
                $this.Eat([TT]::LBRACKET)
                $elems = [System.Collections.Generic.List[object]]::new()
                while (-not $this.Check([TT]::RBRACKET)) {
                    if ($this.Check([TT]::COMMA)) { $elems.Add($null); $this.Pos++; continue }
                    if ($this.Check([TT]::ELLIPSIS)) {
                        $this.Eat([TT]::ELLIPSIS)
                        $elems.Add(@{ type = 'SpreadElement'; argument = $this.ParseAssignment() })
                    } else { $elems.Add($this.ParseAssignment()) }
                    $this.TryEat([TT]::COMMA) | Out-Null
                }
                $this.Eat([TT]::RBRACKET)
                return @{ type = 'ArrayExpression'; elements = $elems.ToArray() }
            }

            ([TT]::LBRACE) {
                $this.Eat([TT]::LBRACE)
                $props = [System.Collections.Generic.List[hashtable]]::new()
                while (-not $this.Check([TT]::RBRACE)) {
                    if ($this.Check([TT]::ELLIPSIS)) {
                        $this.Eat([TT]::ELLIPSIS)
                        $props.Add(@{ type = 'SpreadElement'; argument = $this.ParseAssignment() })
                        $this.TryEat([TT]::COMMA) | Out-Null; continue
                    }
                    $isAsync = $this.CheckVal('async') -and $this.Peek(1).Type -ne [TT]::COLON
                    if ($isAsync) { $this.Pos++ }
                    $isGen = $this.TryEat([TT]::STAR)
                    $key = $null; $computed = $false
                    if ($this.Check([TT]::LBRACKET)) {
                        $this.Eat([TT]::LBRACKET); $key = $this.ParseAssignment(); $this.Eat([TT]::RBRACKET); $computed = $true
                    } else { $key = $this.Cur().Value; $this.Pos++ }
                    if ($this.Check([TT]::LPAREN)) {
                        $typeParams = $this.ParseTypeParams()
                        $this.Eat([TT]::LPAREN); $params = $this.ParseParams(); $this.Eat([TT]::RPAREN)
                        $retType = $null; if ($this.TryEat([TT]::COLON)) { $retType = $this.ParseType() }
                        $props.Add(@{ type = 'ObjectMethod'; key = $key; computed = $computed; params = $params; returnType = $retType; body = $this.ParseBlock(); async = $isAsync; generator = [bool]$isGen })
                    } elseif ($this.Check([TT]::COLON)) {
                        $this.Eat([TT]::COLON)
                        $props.Add(@{ type = 'ObjectProperty'; key = $key; computed = $computed; value = $this.ParseAssignment() })
                    } else {
                        $props.Add(@{ type = 'ObjectProperty'; key = $key; computed = $false; shorthand = $true })
                    }
                    $this.TryEat([TT]::COMMA) | Out-Null
                }
                $this.Eat([TT]::RBRACE)
                return @{ type = 'ObjectExpression'; properties = $props.ToArray() }
            }

            ([TT]::NEW) {
                $this.Eat([TT]::NEW); $callee = $this.ParseCallMember(); $args = @()
                if ($this.Check([TT]::LPAREN)) { $this.Eat([TT]::LPAREN); $args = $this.ParseArgList(); $this.Eat([TT]::RPAREN) }
                return @{ type = 'NewExpression'; callee = $callee; args = $args }
            }

            ([TT]::FUNCTION) { return $this.ParseFunctionDecl(@(), @()) }
            ([TT]::CLASS) { return $this.ParseClassDecl(@(), @()) }

            ([TT]::ASYNC) {
                $this.Eat([TT]::ASYNC)
                return $this.ParseArrowOrParen($true)
            }

            default { throw "unexpected token $($t.Type) ('$($t.Value)') at L$($t.Line):$($t.Col)" }
        }
        return $null
    }

    [hashtable] ParseArrowOrParen([bool]$isAsync = $false) {
        if ($this.Check([TT]::IDENT) -and $this.Peek(1).Type -eq [TT]::ARROW) {
            $param = $this.Eat([TT]::IDENT).Value; $this.Eat([TT]::ARROW)
            $body = if ($this.Check([TT]::LBRACE)) { $this.ParseBlock() } else { $this.ParseAssignment() }
            return @{ type = 'ArrowFunction'; async = $isAsync; params = @(@{ type = 'Parameter'; name = $param }); body = $body }
        }
        $this.Eat([TT]::LPAREN); $params = $this.ParseParams(); $this.Eat([TT]::RPAREN)
        $retType = $null; if ($this.TryEat([TT]::COLON)) { $retType = $this.ParseType() }
        $this.Eat([TT]::ARROW)
        $body = if ($this.Check([TT]::LBRACE)) { $this.ParseBlock() } else { $this.ParseAssignment() }
        return @{ type = 'ArrowFunction'; async = $isAsync; params = $params; returnType = $retType; body = $body }
    }
}

class SSAEmitter {
    [int]$TempCounter = 0
    [int]$LabelCounter = 0
    [System.Collections.Generic.List[string]]$Instructions

    SSAEmitter() { $this.Instructions = [System.Collections.Generic.List[string]]::new() }

    [string] NewTemp() { return "%t$($this.TempCounter++)" }
    [string] NewLabel() { return "L$($this.LabelCounter++)" }
    [void] Emit([string]$i) { $this.Instructions.Add($i) }

    [string] EmitExpr([object]$node) {
        if ($null -eq $node) { return 'undef' }
        switch ($node.type) {
            'Literal' {
                $tmp = $this.NewTemp(); $this.Emit("$tmp = const $($node.value)"); return $tmp
            }
            'Identifier' { return $node.name }
            'TemplateLiteral' {
                $tmp = $this.NewTemp(); $this.Emit("$tmp = template `"$($node.value)`""); return $tmp
            }
            'BinaryExpression' {
                $l = $this.EmitExpr($node.left); $r = $this.EmitExpr($node.right); $tmp = $this.NewTemp()
                $op = switch ($node.operator) {
                    '+' { 'add' }; '-' { 'sub' }; '*' { 'mul' }; '/' { 'div' }
                    '%' { 'mod' }; '**' { 'pow' }; '&' { 'band' }; '|' { 'bor' }
                    '^' { 'bxor' }; '<<' { 'shl' }; '>>' { 'shr' }; '>>>' { 'ushr' }
                    '==' { 'eq' }; '!=' { 'neq' }; '===' { 'seq' }; '!==' { 'sneq' }
                    '<' { 'lt' }; '>' { 'gt' }; '<=' { 'lte' }; '>=' { 'gte' }
                    '??' { 'nullish' }; 'instanceof' { 'instanceof' }; 'in' { 'in' }
                    default { $node.operator }
                }
                $this.Emit("$tmp = $op $l, $r"); return $tmp
            }
            'LogicalExpression' {
                $l = $this.EmitExpr($node.left); $lEnd = $this.NewLabel(); $tmp = $this.NewTemp()
                $this.Emit("$tmp = mov $l")
                $this.Emit("branch_$($node.operator) $l, $lEnd")
                $r = $this.EmitExpr($node.right)
                $this.Emit("$tmp = mov $r")
                $this.Emit("${lEnd}:")
                return $tmp
            }
            'UnaryExpression' {
                $op = switch ($node.operator) { '!' {'not'} '-' {'neg'} '+' {'pos'} '~' {'bnot'} 'typeof' {'typeof'} 'void' {'void'} 'delete' {'delete'} default {$node.operator} }
                $val = $this.EmitExpr($node.operand); $tmp = $this.NewTemp()
                $this.Emit("$tmp = $op $val"); return $tmp
            }
            'UpdateExpression' {
                $val = $this.EmitExpr($node.operand); $tmp = $this.NewTemp()
                if ($node.prefix) {
                    $op = if ($node.operator -eq '++') { 'add' } else { 'sub' }
                    $this.Emit("$tmp = $op $val, 1")
                    $this.Emit("$($node.operand.name) = mov $tmp")
                } else {
                    $this.Emit("$tmp = mov $val")
                    $op = if ($node.operator -eq '++') { 'add' } else { 'sub' }
                    $new = $this.NewTemp(); $this.Emit("$new = $op $val, 1")
                    if ($node.operand.name) { $this.Emit("$($node.operand.name) = mov $new") }
                }
                return $tmp
            }
            'AssignmentExpression' {
                $rhs = $this.EmitExpr($node.right)
                if ($node.operator -eq '=') {
                    $target = if ($node.left.name) { $node.left.name } else { $this.EmitExpr($node.left) }
                    $this.Emit("$target = mov $rhs"); return $target
                } else {
                    $lhs = $this.EmitExpr($node.left); $op = $node.operator.TrimEnd('=')
                    $tmp = $this.NewTemp(); $this.Emit("$tmp = $op $lhs, $rhs")
                    $target = if ($node.left.name) { $node.left.name } else { $lhs }
                    $this.Emit("$target = mov $tmp"); return $target
                }
            }
            'TernaryExpression' {
                $cond = $this.EmitExpr($node.condition)
                $lTrue = $this.NewLabel(); $lFalse = $this.NewLabel(); $lEnd = $this.NewLabel(); $tmp = $this.NewTemp()
                $this.Emit("branch $cond, $lTrue, $lFalse")
                $this.Emit("${lTrue}:"); $tv = $this.EmitExpr($node.then); $this.Emit("$tmp = mov $tv"); $this.Emit("jump $lEnd")
                $this.Emit("${lFalse}:"); $fv = $this.EmitExpr($node.else); $this.Emit("$tmp = mov $fv")
                $this.Emit("${lEnd}:"); return $tmp
            }
            'CallExpression' {
                $callee = $this.EmitExpr($node.callee)
                $argTemps = foreach ($a in $node.args) { $this.EmitExpr($a) }
                $tmp = $this.NewTemp(); $this.Emit("$tmp = call $callee($($argTemps -join ', '))"); return $tmp
            }
            'NewExpression' {
                $callee = $this.EmitExpr($node.callee)
                $argTemps = foreach ($a in $node.args) { $this.EmitExpr($a) }
                $tmp = $this.NewTemp(); $this.Emit("$tmp = new $callee($($argTemps -join ', '))"); return $tmp
            }
            'MemberExpression' {
                $obj = $this.EmitExpr($node.object); $tmp = $this.NewTemp()
                if ($node.computed) { $idx = $this.EmitExpr($node.property); $this.Emit("$tmp = index $obj[$idx]") }
                else { $this.Emit("$tmp = field $obj.$($node.property)") }
                return $tmp
            }
            'ArrayExpression' {
                $tmp = $this.NewTemp()
                $elts = foreach ($e in $node.elements) { if ($null -ne $e) { $this.EmitExpr($e) } else { 'hole' } }
                $this.Emit("$tmp = array [$($elts -join ', ')]"); return $tmp
            }
            'ObjectExpression' {
                $tmp = $this.NewTemp(); $this.Emit("$tmp = object {}")
                foreach ($p in $node.properties) {
                    if ($p.type -eq 'SpreadElement') { $sv = $this.EmitExpr($p.argument); $this.Emit("spread $tmp, $sv") }
                    elseif ($p.shorthand) { $this.Emit("$tmp.$($p.key) = mov $($p.key)") }
                    else { $val = $this.EmitExpr($p.value); $this.Emit("$tmp.$($p.key) = mov $val") }
                }
                return $tmp
            }
            'AsExpression' { return $this.EmitExpr($node.expression) }
            'AwaitExpression' { $v = $this.EmitExpr($node.operand); $tmp = $this.NewTemp(); $this.Emit("$tmp = await $v"); return $tmp }
            'ArrowFunction' {
                $tmp = $this.NewTemp()
                $pnames = foreach ($p in $node.params) { $p.name }
                $this.Emit("$tmp = lambda ($($pnames -join ', ')) { ... }"); return $tmp
            }
            default { $tmp = $this.NewTemp(); $this.Emit("$tmp = opaque ; $($node.type)"); return $tmp }
        }
        return $null
    }

    [void] EmitStmt([object]$node) {
        if ($null -eq $node) { return }
        switch ($node.type) {
            'VariableDeclaration' {
                foreach ($d in $node.declarators) {
                    if ($d.type -eq 'VariableDeclarator') {
                        if ($null -ne $d.initializer) { $val = $this.EmitExpr($d.initializer); $this.Emit("$($d.name) = mov $val ; $($node.kind)") }
                        else { $this.Emit("$($d.name) = undef ; $($node.kind)") }
                    }
                }
            }
            'ExpressionStatement' { $this.EmitExpr($node.expression) | Out-Null }
            'ReturnStatement' {
                if ($node.value) { $v = $this.EmitExpr($node.value); $this.Emit("ret $v") } else { $this.Emit('ret') }
            }
            'IfStatement' {
                $cond = $this.EmitExpr($node.condition)
                $lTrue = $this.NewLabel(); $lEnd = $this.NewLabel()
                $lFalse = if ($node.else) { $this.NewLabel() } else { $lEnd }
                $this.Emit("branch $cond, $lTrue, $lFalse")
                $this.Emit("${lTrue}:"); $this.EmitStmt($node.then)
                if ($node.else) { $this.Emit("jump $lEnd"); $this.Emit("${lFalse}:"); $this.EmitStmt($node.else) }
                $this.Emit("${lEnd}:")
            }
            'WhileStatement' {
                $lTop = $this.NewLabel(); $lBody = $this.NewLabel(); $lEnd = $this.NewLabel()
                $this.Emit("${lTop}:"); $cond = $this.EmitExpr($node.condition)
                $this.Emit("branch $cond, $lBody, $lEnd")
                $this.Emit("${lBody}:"); $this.EmitStmt($node.body)
                $this.Emit("jump $lTop"); $this.Emit("${lEnd}:")
            }
            'ForStatement' {
                $this.EmitStmt($node.init)
                $lTop = $this.NewLabel(); $lBody = $this.NewLabel(); $lEnd = $this.NewLabel()
                $this.Emit("${lTop}:")
                if ($node.condition) { $cond = $this.EmitExpr($node.condition); $this.Emit("branch $cond, $lBody, $lEnd") }
                $this.Emit("${lBody}:"); $this.EmitStmt($node.body)
                if ($node.update) { $this.EmitExpr($node.update) | Out-Null }
                $this.Emit("jump $lTop"); $this.Emit("${lEnd}:")
            }
            'ForOfStatement' {
                $iter = $this.EmitExpr($node.iterable); $it = $this.NewTemp(); $this.Emit("$it = iter $iter")
                $lTop = $this.NewLabel(); $lBody = $this.NewLabel(); $lEnd = $this.NewLabel()
                $this.Emit("${lTop}:"); $next = $this.NewTemp()
                $this.Emit("$next = iter_next $it"); $this.Emit("branch $next, $lBody, $lEnd")
                $this.Emit("${lBody}:"); $this.Emit("$($node.name) = iter_val $next")
                $this.EmitStmt($node.body); $this.Emit("jump $lTop"); $this.Emit("${lEnd}:")
            }
            'BlockStatement' { foreach ($s in $node.body) { $this.EmitStmt($s) } }
            'FunctionDeclaration' {
                $pnames = foreach ($p in $node.params) { $p.name }
                $this.Emit("func $($node.name)($($pnames -join ', ')):")
                $this.EmitStmt($node.body)
                $this.Emit("endfunc $($node.name)")
            }
            'ThrowStatement' { $v = $this.EmitExpr($node.value); $this.Emit("throw $v") }
            'TryCatchStatement' {
                $lTry = $this.NewLabel(); $lCatch = $this.NewLabel(); $lEnd = $this.NewLabel()
                $this.Emit("${lTry}:"); $this.EmitStmt($node.try); $this.Emit("jump $lEnd")
                $this.Emit("${lCatch}:")
                if ($node.catch) {
                    if ($node.catch.param) { $this.Emit("$($node.catch.param) = catch_val") }
                    $this.EmitStmt($node.catch.body)
                }
                $this.Emit("${lEnd}:")
                if ($node.finally) { $this.Emit("; finally"); $this.EmitStmt($node.finally) }
            }
            'BreakStatement'{ $this.Emit('jump <break>') }
            'ContinueStatement' { $this.Emit('jump <continue>') }
            default { $this.EmitExpr($node) | Out-Null }
        }
    }

    [void] EmitProgram([object[]]$program) {
        foreach ($stmt in $program) { $this.EmitStmt($stmt) }
    }
}

$File = Resolve-Path $File
if (-not (Test-Path $File)) { throw "file not found: $File" }

$code = Get-Content $File -Raw
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($File)
if ($Mode -eq 'ast') { $outExt = 'json' }
elseif ($Mode -eq 'ssa') { $outExt = 'il' }
$outFile = Join-Path (Split-Path $File) "$baseName.$outExt"

$lexer = [Lexer]::new($code)
$tokens = $lexer.Tokenize()

$parser = [Parser]::new($tokens)
$program = $parser.ParseProgram()

if ($Verbose -and $parser.Errors.Count -gt 0) {
    $parser.Errors | ForEach-Object { Write-Warning $_ }
}

if ($Mode -eq 'ast') {
    $program | ConvertTo-Json -Depth 30 | Set-Content $outFile -Encoding UTF8
} elseif ($Mode -eq 'ssa') {
    $emitter = [SSAEmitter]::new()
    $emitter.EmitProgram($program)
    $emitter.Instructions | Set-Content $outFile -Encoding UTF8
}

if ($Verbose) {
    Write-Host "wrote $outFile" -ForegroundColor Green
} else {
    $outFile
}