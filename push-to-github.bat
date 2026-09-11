@echo off
chcp 936 >nul
title 推送「她的信息本-iOS」到 GitHub
setlocal EnableDelayedExpansion

REM ════════════════════════════════════════════════════════════════
REM  她的信息本-iOS → GitHub   推送脚本 v5
REM
REM  v1 的教训：一上来就 push，失败了只说「推送失败」——
REM  用户无从判断是地址写错、登录没过、还是网络不通，
REM  只能在错的地方反复试。
REM
REM  v3 的教训：把「网络不通」当成终点是错的。
REM  实测这台机器到 github.com:443 的连接时通时断（报 21 秒连接超时，
REM  过几分钟再试就通了）。所以 v3 在「测地址」和「推送」两处都加了
REM  自动重试：网络类失败先原地重试 3 次，重试完还不通再谈换网络。
REM
REM  v4 的教训（最容易骗人的一个）：
REM    a. 「远程非空」不等于「要覆盖」。推成功过一次之后远程永远非空，
REM       而那时候本地和远程通常是「快进」关系 —— 快进是零损失的。
REM       v3 在这里问了一句「要不要覆盖」，用户按 N 就成了「失败」。
REM       现在只有真的分叉（各有对方没有的提交）才会问。
REM    b. 「git push 退出码为 0」不等于「推上去了」。退出码在管道里会被
REM       吃掉，网络半途断掉时 git 也可能先报成功再失败。所以收尾不再看
REM       退出码，而是拿 ls-remote 的真实 SHA 和本地 HEAD 逐字比对。
REM    c. 「没报错」也不等于「网络没问题」。系统级 gitconfig 里的
REM       credential.helper=helper-selector 每次认证空跑 40 秒，push 要认证
REM       两回 = 80 秒，命令被超时掐死且**一个字都不打印** —— 现场看着
REM       就是「网络不通」。现在推送前会把它绕开（见 :tune_creds）。
REM
REM  v5 的更正（补上 v4-c 没说透的那一半）：
REM    credential.helper 是【累加】的，不是覆盖 —— 所以「global 已经指向
REM    GCM」并不能免除那 40 秒，system 里那条 selector 照样会跑一遍。
REM    正确的绕法是：在优先级最高的一层写一条**空值**（空值会清空前面积累
REM    的全部 helper），再显式指定要用的 GCM。
REM    本脚本在仓库级做了这件事；同时全局 ~/.gitconfig 也已经修好，
REM    所以其他项目也不用再白等那 40 秒。
REM    用的是短名 manager，不写绝对路径 —— WorkBuddy 升级便携版 git 之后
REM    版本号会变（…/versions/1.2.0/…），写死路径会直接失效。
REM
REM  v2 改成「先诊断，再推送」：
REM    1. 先测这个地址到底连不连得上，并把 git 的原始输出原样打出来
REM    2. 连不上时按 找不到仓库 / 登录被拒 / 网络不通 分别给处置办法
REM    3. 找不到仓库时，顺手列出你账号下真实存在的仓库名
REM    4. 推送前先判断本地和远程是「快进 / 已同步 / 分叉」中的哪一种
REM    5. 全过程写一份「推送日志.txt」，可以直接发给别人看
REM ════════════════════════════════════════════════════════════════
REM ────────────────────────────────────────────────────────────────
REM  【编码铁律】本文件必须是 **GBK(936) 编码 + CRLF 行尾**，两个都不能改。
REM
REM  为什么不能用 UTF-8：cmd 解析 .bat 用的是系统 ANSI 代码页，
REM  `chcp` 只改控制台输出，改不了它读文件的方式。文件若是 UTF-8，
REM  中文会在**行中间**被截断，屏幕上冒出
REM  「'xxx' is not recognized as an internal or external command」；
REM  更糟的是 `set` / `goto` 也可能一起被切断，让脚本随机走错分支。
REM  （实测：UTF-8 那一版跑起来中文注释七零八落，
REM    `set "RESULT_TXT=…"` 被切成两条命令，最后的结论行整条变空。）
REM ────────────────────────────────────────────────────────────────

set "HERE=%~dp0"
set "LOG=%HERE%推送日志.txt"
set "TMPERR=%TEMP%\hi_push_err.txt"
set "TMPCNT=%TEMP%\hi_push_cnt.txt"
set "URL="
set "GITEXE="
set "TRIES=0"
set "PUSHMODE="
set "ATT=0"
set "PUSH_ATT=0"

echo.
echo ============================================================
echo   把「她的信息本-iOS」推送到 GitHub
echo ============================================================
echo.

REM ═══════════ 1/6 找 git ═══════════
REM 这台机器上 git 不在系统 PATH 里，所以按「便携版 → 正式版 → PATH」的顺序找
REM ① 随工具附带的 PortableGit（本机就是这种，版本号通配，不写死）
for /d %%v in ("%USERPROFILE%\.workbuddy\binaries\PortableGit\versions\*") do (
  if exist "%%v\cmd\git.exe" set "GITEXE=%%v\cmd\git.exe"
)
REM ② 正式安装的 Git for Windows
if not defined GITEXE if exist "%ProgramFiles%\Git\cmd\git.exe" set "GITEXE=%ProgramFiles%\Git\cmd\git.exe"
if not defined GITEXE if exist "%ProgramFiles(x86)%\Git\cmd\git.exe" set "GITEXE=%ProgramFiles(x86)%\Git\cmd\git.exe"
REM ③ 兜底：PATH 里能找到就用
if not defined GITEXE for /f "delims=" %%i in ('where git 2^>nul') do (
  if not defined GITEXE set "GITEXE=%%i"
)
if not defined GITEXE goto :err_nogit

echo   [1/6] git 已就绪
echo         !GITEXE!
echo.

REM ═══════════ 2/6 进入本脚本所在的目录 ═══════════
REM 用 %~dp0（脚本自身所在目录）而不写路径 —— 这样脚本里不出现任何中文路径
pushd "%HERE%"
if errorlevel 1 goto :err_nodir

echo   [2/6] 工作目录
echo         %CD%
echo.

REM ═══════════ 3/6 确认这里是一个 git 仓库 ═══════════
"!GITEXE!" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto :err_notrepo

set "NSTATUS=干净"
for /f "delims=" %%s in ('"!GITEXE!" status --porcelain 2^>nul') do set "NSTATUS=有未提交改动"
echo   [3/6] 本地最新提交
"!GITEXE!" log --oneline -1
set "NCOMMIT="
for /f "delims=" %%c in ('"!GITEXE!" rev-list --count HEAD 2^>nul') do set "NCOMMIT=%%c"
if not defined NCOMMIT set "NCOMMIT=?"
echo          （本地一共 !NCOMMIT! 个提交，工作区 %NSTATUS%）
echo.

REM ═══════════ 4/6 环境自查：代理 ═══════════
REM 代理是「推送失败」里最隐蔽的一类：它在 git 之外，配错了报错却像网络问题
if defined HTTPS_PROXY goto :warn_proxy
if defined HTTP_PROXY goto :warn_proxy
if defined ALL_PROXY goto :warn_proxy
goto :env_ok

:warn_proxy
echo         ! 检测到代理环境变量：
if defined HTTPS_PROXY echo             HTTPS_PROXY=!HTTPS_PROXY!
if defined HTTP_PROXY  echo             HTTP_PROXY=!HTTP_PROXY!
if defined ALL_PROXY   echo             ALL_PROXY=!ALL_PROXY!
echo           如果这个代理没在运行，推送会以「网络不通」的形态失败。
echo           脚本稍后会自动再试一次「绕开代理」的直连。
echo.

:env_ok

REM ═══════════ 5/6 确认并测试远程地址 ═══════════
REM 先把登录方式配好 —— 下面的地址探测就需要它，否则 ls-remote 拿不到凭据，
REM 会把「登录没过」误报成「找不到仓库」。
REM
REM  【v4 修 · 本次失败的真凶】不再粗暴地写 `config --global credential.helper manager`。
REM  本机实测瓶颈在**系统级** gitconfig 的 `credential.helper=helper-selector`：
REM  这个「凭据助手选择器」每次认证要空跑约 40 秒（它挨个探测环境里有哪些
REM  可用的凭据助手），而 git push 一次要认证两回 —— 80 秒就这么没了。
REM  后果极具迷惑性：命令在超时线上被掐死，屏幕上**一个字的错误都没有**，
REM  看起来就是「网络不通」，于是人就被赶到换网络、查防火墙的方向去了。
REM  （实测对照：绕开它之后，同一次推送从「超时」变成 5 秒。）
call :tune_creds

:ask_url
set "CURURL="
for /f "delims=" %%u in ('"!GITEXE!" remote get-url origin 2^>nul') do set "CURURL=%%u"

if not defined CURURL goto :url_new

echo   [4/6] 远程地址
echo         当前：!CURURL!
echo.
echo         直接按回车 = 就用这个；要换 = 粘贴新地址再回车
set "NEWURL="
set /p "NEWURL=  地址: "
if not defined NEWURL (
  set "URL=!CURURL!"
) else (
  "!GITEXE!" remote set-url origin "!NEWURL!"
  set "URL=!NEWURL!"
)
goto :url_test

:url_new
echo   [4/6] 还没有远程地址
echo.
echo         打开你的仓库网页，点绿色的 Code 按钮，复制 HTTPS 那一行。
echo         它长这样：https://github.com/你的用户名/仓库名.git
echo.
set "URL="
set /p "URL=  地址: "
if not defined URL goto :err_nourl
"!GITEXE!" remote add origin "!URL!"
if errorlevel 1 goto :err_remoteadd
echo.
echo         OK  已关联：!URL!
echo.

:url_test
set /a TRIES+=1
echo   [5/6] 正在测试这个地址（地址不对的话，这里就会告诉你）…
echo.

REM 到 github.com 的通路在国内经常是「一阵通、一阵不通」：
REM 实测同一台机器，21 秒连接超时之后过几分钟再试就通了。
REM 所以连不上先原地重试两次，别急着让用户去换网络。
set "ATT=0"
:url_test_retry
set /a ATT+=1
"!GITEXE!" ls-remote --heads "!URL!" >"%TMPERR%" 2>&1
if not errorlevel 1 goto :url_ok

call :kindof
if not "!KIND!"=="NETWORK" goto :url_test_decided
if !ATT! GEQ 3 goto :url_test_decided
echo         没连上（第 !ATT! 次）。等 4 秒重试 —— 这条通路经常是一阵
echo         一阵的，重试一次往往就通了。
timeout /t 4 /nobreak >nul
goto :url_test_retry

:url_test_decided

REM 只有「网络类」失败才值得绕开代理重试。
REM 仓库名写错也会失败，但那跟代理没关系 —— 绕开代理重试
REM 只会把诊断带偏（把「找不到仓库」变成「网络不通」）。
if not "!KIND!"=="NETWORK" goto :report
if not defined HTTPS_PROXY if not defined HTTP_PROXY if not defined ALL_PROXY goto :report

echo         代理这条路过不去，绕开代理再试一次 …
set "HTTPS_PROXY="
set "HTTP_PROXY="
set "ALL_PROXY="
set "https_proxy="
set "http_proxy="
"!GITEXE!" ls-remote --heads "!URL!" >"%TMPERR%" 2>&1
if not errorlevel 1 (
  echo         OK  直连可以，本次推送会绕开代理。
  echo.
  goto :url_ok
)
call :kindof

:report
REM 把 git 的原始输出原样打出来 —— 这是 v1 缺的东西
echo         ── git 的原始输出 ─────────────────────────
type "%TMPERR%"
echo         ──────────────────────────────────────────
echo.

if "!KIND!"=="NOTFOUND" goto :case_notfound
if "!KIND!"=="AUTH"     goto :case_auth
if "!KIND!"=="NETWORK"  goto :case_network
goto :case_other


REM ════════════════════════════════════════════════════════════════
REM  把 git 的报错归类（只设 KIND，不打印）
REM
REM  按「优先级从低到高」依次覆盖 —— 最后匹配上的那一类赢。
REM  不要写成 `if not defined KIND findstr ... && set "KIND=X"`：
REM  条件为假时 cmd 仍可能执行 && 后面的 set（if 自身返回 0），分类会错。
REM ════════════════════════════════════════════════════════════════
:kindof
set "KIND=OTHER"
findstr /i /c:"not found" /c:"404" /c:"does not exist" /c:"access denied" "%TMPERR%" >nul 2>&1 && set "KIND=NOTFOUND"
findstr /i /c:"authentication failed" /c:"could not read username" /c:"invalid username or password" /c:"403" /c:"terminal prompts disabled" "%TMPERR%" >nul 2>&1 && set "KIND=AUTH"
findstr /i /c:"could not resolve" /c:"failed to connect" /c:"timed out" /c:"connection refused" /c:"connection reset" /c:"was reset" /c:"recv failure" /c:"connect tunnel failed" /c:"network is unreachable" /c:"ssl" "%TMPERR%" >nul 2>&1 && set "KIND=NETWORK"
exit /b 0

REM ════════════════════════════════════════════════════════════════
REM  绕开「凭据助手选择器」
REM
REM  系统级 gitconfig 里有 `credential.helper=helper-selector`，它每次认证
REM  要空跑约 40 秒。git push 一次认证两回 = 80 秒，命令直接被超时掐死，
REM  而且**不打印任何错误** —— 现场看起来就是「网络不通」。
REM
REM  绕法：在**仓库级**配置里先写一个空值。git 规定 credential.helper 出现
REM  空值时会清空前面累积的列表，于是系统级那条选择器就被屏蔽掉了；
REM  再把用户级已经配好的 git-credential-manager 原样搬过来接上。
REM  只动这个仓库，不动全局配置，也不动系统配置。
REM
REM  这里必须关掉延迟展开：要搬的值形如 !"C:/…/git-credential-manager.exe"，
REM  开着延迟展开的话那个感叹号会被当成变量引用、把整段值吃掉。
REM ════════════════════════════════════════════════════════════════
REM ── 绕开 system 级的「凭据助手选择器」───────────────────────────
REM  helper-selector 每次认证要空跑 40 秒，而一次 push 要认证两次（取 + 存）
REM  = 80 秒，足以把命令拖过超时线，而且屏幕上一个字都不会打出来。
REM
REM  注意 credential.helper 是【累加】的，不是覆盖：即使 global 已经指向 GCM，
REM  system 里那条 selector 依然会被调用一次。
REM  所以这里先在 local 写一条空值 —— 空值会清空前面积累的全部 helper ——
REM  再显式加一条 GCM，selector 就整条被摘掉了。
REM
REM  用 PATH 里的短名 manager，不写绝对路径：写死绝对路径会在
REM  WorkBuddy 升级便携版 git（…/PortableGit/versions/x.y.z/…）之后直接失效。
:tune_creds
setlocal disabledelayedexpansion
set "UH="
for /f "delims=" %%h in ('"%GITEXE%" config --global --get-all credential.helper 2^>nul') do if not defined UH if not "%%h"=="" set "UH=%%h"
if not defined UH set "UH=manager"
"%GITEXE%" config --local --replace-all credential.helper "" 2>nul
"%GITEXE%" config --local --add credential.helper "%UH%" 2>nul
if errorlevel 1 goto :tune_creds_out
echo         OK  已绕开凭据助手选择器（它每次认证要空跑 40 秒）
:tune_creds_out
endlocal
exit /b 0

REM ── 情况一：找不到这个仓库（最常见：仓库名写错）──────────────
:case_notfound
echo         [判断] 登录这关过了，但这个地址下没有你能访问的仓库。
echo                最可能的原因是地址里「用户名」或「仓库名」差了一个字。
echo.
if !TRIES! GEQ 4 goto :err_toomany

REM 顺手查一下这个账号下真实存在的仓库 —— 让用户自己去猜强得多
set "ACCT="
for /f "tokens=1,2,3,4,5 delims=/" %%a in ("!URL!") do set "ACCT=%%d"
if not defined ACCT goto :notfound_reprompt
where curl >nul 2>&1 || goto :notfound_reprompt
echo         ── 账号 !ACCT! 下的公开仓库（查一下有没有你要的那个）──
curl -s --max-time 12 "https://api.github.com/users/!ACCT!/repos?per_page=100&sort=updated" 2>nul | findstr /i "full_name"
echo         ── 查完 ──────────────────────────────────
echo.
echo         （如果你要的仓库不在上面，说明它是私有的 —— 那也算正常，
echo           私有仓库不会出现在这个公开列表里。）
echo.

:notfound_reprompt
echo         请打开仓库网页，把浏览器地址栏里的地址整行复制过来：
echo         （形如 https://github.com/haohao234/仓库名 —— .git 有没有都行）
echo.
set "AGAIN="
set /p "AGAIN=  地址: "
if not defined AGAIN goto :err_url_abort
"!GITEXE!" remote set-url origin "!AGAIN!"
set "URL=!AGAIN!"
echo.
goto :url_test

:url_ok
echo         OK  地址可用，仓库存在。
echo.

REM ═══════════ 6/6 本地和远程是什么关系 ═══════════
REM
REM  【v4 修掉的核心 bug】v3 把「远程非空」直接当成「两条无关历史、必须覆盖」。
REM  可是远程只要推成功过一次就永远非空 —— 于是第二次以后每次跑脚本，
REM  它都拿「你上次自己推上去的提交」来问你「要不要覆盖」。
REM  用户不敢按 Y、按 N 退出，屏幕上留下的是「已取消」，
REM  看起来就是「又推送失败了」，而真正的原因是脚本问错了问题。
REM
REM  该问的不是「远程空不空」，而是「本地能不能快进」：
REM      远程是本地历史的祖先 → 快进推送，零损失，不该问
REM      两边 SHA 一样         → 已经同步，什么都不用做
REM      两边各有对方没有的提交 → 这才是唯一该问「要不要覆盖」的情况
echo   [6/6] 比较本地和远程 …
"!GITEXE!" fetch origin "+refs/heads/main:refs/remotes/origin/main" >"%TMPERR%" 2>&1
REM  refspec 必须写成完整形式：`fetch origin main` 只写 FETCH_HEAD，
REM  不更新 refs/remotes/origin/main —— 那样 git status 会一直显示 [gone]，
REM  看着像「远程分支丢了」，其实只是本地从来没把远程分支记下来。

set "RCOUNT=0"
set "LHEAD="
set "RHEAD="
"!GITEXE!" rev-parse --verify -q FETCH_HEAD >nul 2>&1
if errorlevel 1 goto :no_remote_main

for /f "delims=" %%c in ('"!GITEXE!" rev-list --count FETCH_HEAD 2^>nul') do set "RCOUNT=%%c"
if not defined RCOUNT set "RCOUNT=0"
for /f "delims=" %%h in ('"!GITEXE!" rev-parse HEAD 2^>nul') do set "LHEAD=%%h"
for /f "delims=" %%h in ('"!GITEXE!" rev-parse FETCH_HEAD 2^>nul') do set "RHEAD=%%h"
echo         远程 main 上有 !RCOUNT! 个提交
echo           远程最新 !RHEAD:~0,7!  /  本地最新 !LHEAD:~0,7!
echo.

if /i "!RHEAD!"=="!LHEAD!" goto :already_synced

"!GITEXE!" merge-base --is-ancestor FETCH_HEAD HEAD >nul 2>&1
if not errorlevel 1 goto :push_fastforward

goto :ask_overwrite


:no_remote_main
REM  仓库刚建、还没有 main 分支，或者这次 fetch 只是被网络抖掉了。
REM  两种情况处置一样：直接推一次试试，不吓唬用户。
echo         远程还没有 main 分支（新仓库），直接推。
echo.
goto :push_normal


:already_synced
echo         OK  本地和远程已经一致，没有需要推送的内容。
echo.
goto :verify_after


:push_fastforward
echo         OK  可以快进：远程那 !RCOUNT! 个提交本地都有，
echo             这次推送只会往后加，不会覆盖任何东西。
echo.
goto :push_normal


:push_normal
echo         正在推送 …
echo         （公开仓库读取不用登录，但推送要 —— 这里可能弹一次 GitHub 登录窗口）
set "PUSHMODE="
call :push_retry
if errorlevel 1 goto :err_push
goto :verify_after


:ask_overwrite
REM  只有走到这里才是真的分叉：本地和远程各自握有对方没有的提交。
echo         ! 这次不是快进 —— 本地和远程各有对方没有的提交，
echo           直接推会被拒绝（rejected / fetch first）。
echo.
echo         远程比本地多出来的那一条是：
"!GITEXE!" log --oneline -1 FETCH_HEAD
echo.
echo         覆盖之后，上面这一条连同它的历史在远程就查不到了。
echo         如果它只是建仓库时自动生成的 Initial commit，覆盖没有损失；
echo         如果是你自己写的东西，先按 N 退出，去备份。
echo.
set "FORCE="
set /p "FORCE=  覆盖并推送？(Y/N) "
if /i not "!FORCE!"=="Y" goto :err_abort_force

echo.
echo         正在覆盖 …
echo         （公开仓库读取不用登录，但推送要 —— 这里可能弹一次 GitHub 登录窗口）
set "PUSHMODE=--force"
call :push_retry
if errorlevel 1 goto :err_push
goto :verify_after

REM ════════════════════════════════════════════════════════════════
REM  收尾：核对远程的真实 SHA，而不是相信 git 的退出码
REM
REM  【v4 新增】git 的「成功」会骗人，实测过两种：
REM    1. `git push 2>&1 | tail -3` 之后 $? 是 tail 的退出码，永远是 0
REM    2. 网络半途断掉时，git 可能先打印一段像是成功的内容再报错
REM  唯一客观的判据是「远程实际的 SHA 和本地是否相同」——
REM  这也正是本脚本以后判断「到底成没成」的唯一依据。
REM ════════════════════════════════════════════════════════════════
:verify_after
echo.
echo   [核对] 确认 GitHub 上到底是哪一条提交 …
set "RSHA="
for /f "tokens=1" %%s in ('"!GITEXE!" ls-remote origin refs/heads/main 2^>nul') do set "RSHA=%%s"
set "LSHA="
for /f "delims=" %%s in ('"!GITEXE!" rev-parse HEAD 2^>nul') do set "LSHA=%%s"
echo         本地 HEAD  !LSHA:~0,7!

if not defined RSHA (
  echo         远程 HEAD  读不到 —— 只是这次查询被网络抖掉了，
  echo                    不代表没推上去。
  echo.
  echo         ! 没能核对上。代码很可能已经在 GitHub 上了：
  echo           先把仓库网页刷新看一眼（地址见下），
  echo           若确实没上去，重新双击本脚本跑第二遍即可 ——
  echo           第二遍几秒钟就完事，不会重复推任何东西。
  echo.
  set "RESULT_TXT=推送已执行，但核对时读不到远程（网络抖动）"
  goto :done
)

echo         远程 HEAD  !RSHA:~0,7!
echo.
if /i "!RSHA!"=="!LSHA!" (
  echo         OK  已核对：GitHub 上的内容和你本地完全一致。
  set "RESULT_TXT=推送成功（已核对远程与本地一致）"
) else (
  echo         ! 两边还差一截（远程 !RSHA:~0,7! / 本地 !LSHA:~0,7!）。
  echo           多半是刚才网络又抖了一下。重新双击本脚本再跑一次 ——
  echo           第二遍会走「快进」，几秒钟完事，不会重复推。
  set "RESULT_TXT=推送后核对不一致（远程 !RSHA:~0,7! / 本地 !LSHA:~0,7!）"
)

:done
set "WEBURL=!URL:.git=!"
echo.
echo ============================================================
echo   OK  !RESULT_TXT!
echo ============================================================
echo.
echo   仓库网页：!WEBURL!
echo.
echo   接着看编译结果：
echo     1. 打开上面的网页，点上方「Actions」标签
echo     2. 点最新那一条「iOS 编译检查」
echo     3. 绿色勾 = 编译通过，不用管；红叉才需要把错误发给我
echo.
echo   本次过程已记录到：推送日志.txt
echo.
call :savelog "!RESULT_TXT!"
popd
pause
exit /b 0


REM ════════════════════════════════════════════════════════════════
REM  推送（含网络类失败的自动重试）
REM
REM  调用前把 !PUSHMODE! 设成 "--force" 或留空。
REM  返回 errorlevel 0 = 成功；非 0 = 失败（%TMPERR% 是最后一次的原始输出）。
REM
REM  为什么必须重试：这台机器实测到 github.com:443 时通时断，
REM  失败信息是「Failed to connect … after 21033 ms」。这类失败与地址、
REM  账号都无关，原地等几秒重来一次就好 —— 直接判定「网络不通」会把
REM  用户赶到错误的排查方向（去换网络、去查防火墙）。
REM ════════════════════════════════════════════════════════════════
:push_retry
set /a PUSH_ATT=0
:push_retry_loop
set /a PUSH_ATT+=1
"!GITEXE!" push -u origin main !PUSHMODE! >"%TMPERR%" 2>&1
if not errorlevel 1 exit /b 0
call :kindof
if not "!KIND!"=="NETWORK" exit /b 1
if !PUSH_ATT! GEQ 3 exit /b 1
echo         连接被中断（第 !PUSH_ATT! 次）。等 5 秒自动重试 …
timeout /t 5 /nobreak >nul
goto :push_retry_loop


REM ════════════════════════════════════════════════════════════════
REM   出错分支
REM ════════════════════════════════════════════════════════════════

:err_nogit
echo   [X] 找不到 git.exe
echo.
echo       请先安装 Git for Windows（装完再双击本脚本）：
echo       https://git-scm.com/download/win
echo.
pause
exit /b 1

:err_nodir
echo   [X] 无法进入脚本所在的文件夹
echo       请把本脚本放在「她的信息本-iOS」文件夹里再运行
echo.
pause
exit /b 1

:err_notrepo
echo   [X] 这个文件夹不是 git 仓库
echo.
echo       本脚本必须放在「她的信息本-iOS」文件夹里（和 project.yml 同一层）
echo       请确认位置后重新双击
echo.
pause
popd
exit /b 1

:err_nourl
echo.
echo   [X] 没有输入地址，已取消（什么都没有改动）
echo.
pause
popd
exit /b 1

:err_remoteadd
echo.
echo   [X] 关联远程仓库失败
echo       检查一下地址拼写，特别是用户名和仓库名
echo.
call :savelog "关联远程仓库失败"
pause
popd
exit /b 1

:err_url_abort
echo.
echo   [X] 没有输入新地址，已取消（本地提交都在，没有丢任何东西）
echo.
call :savelog "地址确认失败，用户取消"
pause
popd
exit /b 1

:err_toomany
echo   [X] 连续 4 次都找不到这个仓库，先停下来。
echo.
echo       请确认这两件事：
echo         1. 仓库确实已经建好了（网页上能打开）
echo         2. 地址栏里的地址和你粘贴的完全一致
echo.
echo       还有一种情况：仓库在你的另一个 GitHub 账号下 ——
echo       看仓库网页右上角头像是哪个账号，地址里的用户名要和它一致。
echo.
call :savelog "连续 4 次仓库地址不存在"
pause
popd
exit /b 1

:case_auth
echo         [判断] 卡在登录这一关（git 没能拿到可用的凭据）。
echo.
echo         怎么处理：
echo           1. 重新双击本脚本再试一次 —— 它会把登录窗口再唤起一次
echo           2. 如果弹的是黑底白字的 Username / Password 框：
echo                用户名 填你的 GitHub 用户名
echo                密码   填 Personal Access Token（GitHub 早已禁用账号密码）
echo           3. 建 Token：github.com/settings/tokens → Generate new token
echo                勾 repo 权限，生成后立刻复制（只显示一次）
echo           4. 还不行就清掉旧凭据：控制面板 → 凭据管理器 →
echo                Windows 凭据 → 删掉 github.com 那一条，再重跑
echo.
call :savelog "登录失败（凭据问题）"
pause
popd
exit /b 1

:case_network
echo         [判断] 网络没能连上 github.com（不是地址、也不是登录的问题）。
echo.
echo         这类失败绝大多数是「一阵一阵的」——本机实测同一个地址，
echo         21 秒连接超时之后过几分钟再试就通了。
echo         本次已经自动重试 3 次都没通，说明此刻这条路确实是断的。
echo.
echo         按省事程度依次试：
echo           1. 什么都不改，过 1-2 分钟重新双击本脚本 —— 最常用的一条
echo           2. 换成手机热点，往往一次就通
echo           3. 如果你开着代理 / VPN，确认它在运行；没开就忽略本条
echo           4. 打开浏览器试 github.com —— 浏览器也打不开，就坐实了是网络
echo.
echo         与仓库地址、GitHub 账号都无关，不要去改地址或重登。
echo.
call :savelog "网络不通（已自动重试 3 次）"
pause
popd
exit /b 1

:case_other
echo         [判断] 上面三类都不匹配，需要看原始输出（就在上面）。
echo.
echo         把这份日志发出去就能定位：
echo         %LOG%
echo.
call :savelog "未分类错误"
pause
popd
exit /b 1

:err_abort_force
echo.
echo   已取消，本地提交都在，没有丢任何东西。
echo.
echo   走到这一步说明本地和远程真的分叉了（各有对方没有的提交）。
echo   想两个都要，就在命令行里手动合并一次：
echo         git pull --rebase origin main
echo         git push origin main
echo   想用本地这份直接盖掉远程，重新双击本脚本、这次按 Y。
echo.
call :savelog "真分叉，用户选择不覆盖"
pause
popd
exit /b 1

:err_push
echo.
echo ============================================================
echo   [X] 推送失败
echo ============================================================
echo.
REM 兜底：万一是被拒绝（远程非空）而我们没提前发现，这里直接处置。
REM 但已经强制推过一次还失败，就不要再回到「被拒绝」分支 —— 那会变成
REM 问一次 Y、推一次、失败、再问一次 Y 的死循环。
set "REJ=0"
if /i not "!PUSHMODE!"=="--force" (
  findstr /i /c:"rejected" /c:"fetch first" /c:"non-fast-forward" /c:"behind" "%TMPERR%" >nul 2>&1
  if not errorlevel 1 set "REJ=1"
)
if "!REJ!"=="1" goto :err_push_rejected

echo   原始输出：
type "%TMPERR%"
echo.
echo   按可能性从高到低排查：
echo.
echo   1. 仓库地址拼错了 —— 用户名或仓库名写错一个字就会失败
echo   2. 登录没过 —— 见上面「登录失败」那一节的四条办法
echo   3. 网络不通 —— 试试手机热点
echo   4. 如果是被拒绝 rejected：远程不是空的，而本脚本这次没能提前发现它，
echo      重跑一次即可（重跑时它会在推送前问你要不要覆盖）
echo.
echo   提示：本地提交还在，不会丢。修好之后重新双击本脚本即可。
echo   完整过程已写进：推送日志.txt
echo.
pause
popd
exit /b 1

:err_push_rejected
echo   远程仓库里有本地没有的提交，所以被拒绝了。
echo.
echo   远程最新一条：
"!GITEXE!" log --oneline -1 FETCH_HEAD 2>nul
echo.
echo   上面那些内容会被本地版本覆盖掉。确认没有损失就输入 Y：
echo.
set "FORCE2="
set /p "FORCE2=  覆盖并推送？(Y/N) "
if /i not "!FORCE2!"=="Y" goto :err_abort_force
echo.
set "PUSHMODE=--force"
call :push_retry
if errorlevel 1 (
  echo.
  echo   [X] 覆盖也失败了，原始输出：
  type "%TMPERR%"
  echo.
  call :savelog "强制推送仍失败"
  pause
  popd
  exit /b 1
)
goto :done


REM ════════════════════════════════════════════════════════════════
REM   写日志（每个出错分支都会调它，方便把问题原样发出去）
REM ════════════════════════════════════════════════════════════════
:savelog
set "RESULT=%~1"
(
  echo 她的信息本-iOS 推送日志
  echo ============================================
  echo 时间      : %DATE% %TIME%
  echo 结果      : !RESULT!
  echo 脚本位置  : %HERE%
  echo 使用的 git: !GITEXE!
  echo 远程地址  : !URL!
  echo 本地提交数: !NCOMMIT!
  echo 远程提交数: !RCOUNT!
  echo ============================================
  echo.
  echo —— git 最后一段原始输出 ——
) >"%LOG%" 2>nul
if exist "%TMPERR%" type "%TMPERR%" >>"%LOG%" 2>nul
exit /b 0
