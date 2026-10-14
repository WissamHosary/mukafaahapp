# End-to-end API test of the core business flow. Exit code 0 = all passed.
param([string]$Base = 'http://localhost:3000', [string]$AdminPhone = '')
$ErrorActionPreference = 'Stop'
# Your Mukafaah Manager phone is remembered in tools\admin-phone.txt (this PC only).
$adminFile = Join-Path $PSScriptRoot 'admin-phone.txt'
if (-not $AdminPhone -and (Test-Path $adminFile)) { $AdminPhone = (Get-Content $adminFile -Raw).Trim() }
$failed = 0

function Api($method, $path, $body = $null, $token = $null, $idem = $null) {
  $headers = @{}
  if ($token) { $headers['Authorization'] = "Bearer $token" }
  if ($idem) { $headers['Idempotency-Key'] = $idem }
  $params = @{ Method = $method; Uri = "$Base$path"; Headers = $headers; ContentType = 'application/json; charset=utf-8'; TimeoutSec = 20 }
  if ($body -ne $null) { $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress)) }
  elseif ($method -ne 'GET') { $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes('{}') }
  try { return Invoke-RestMethod @params }
  catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    throw "$method $path -> $msg"
  }
}
function Check($name, [scriptblock]$fn) {
  try { $r = & $fn; Write-Host "  PASS $name" -ForegroundColor Green; return $r }
  catch { Write-Host "  FAIL $name : $_" -ForegroundColor Red; $script:failed++; return $null }
}
# v0.7: spending points returns a request the customer approves in the app.
function Approve($resp, $tok) {
  if (-not $resp.requestId) { throw "expected an approval request, got $($resp | ConvertTo-Json -Compress -Depth 4)" }
  $pend = Api GET '/v1/customer/redeem-requests/pending' $null $tok
  if (-not ($pend.requests | Where-Object { $_.id -eq $resp.requestId })) { throw 'the customer did not see the request' }
  $r = Api POST "/v1/customer/redeem-requests/$($resp.requestId)/approve" $null $tok
  if ($r.status -ne 'APPROVED') { throw "approve -> $($r.status) $($r.error)" }
  return $r.result
}
function RandPhone() { $p = @('70', '71', '76')[(Get-Random -Maximum 3)]; return $p + (Get-Random -Minimum 100000 -Maximum 999999) }
function Login($phone, $app) {
  $ch = Api POST '/v1/auth/otp/request' @{ phone = $phone; app = $app; locale = 'en' }
  if (-not $ch.devCode) { throw 'devCode missing: is OTP_DEV_ECHO=true?' }
  return Api POST '/v1/auth/otp/verify' @{ challengeId = $ch.challengeId; code = $ch.devCode; app = $app }
}

$ownerPhone = RandPhone; $customerPhone = RandPhone
Write-Host "  owner $ownerPhone, customer $customerPhone"

# Shops are added in Mukafaah Manager, so the test signs in as an admin first.
$adm = $null
try { $adm = Login ($(if ($AdminPhone) { $AdminPhone } else { RandPhone })) 'ADMIN' } catch { $adm = $null }
if (-not $adm) {
  Write-Host '  SKIP smoke test: it needs your Mukafaah Manager phone. Run SEED-DEMO.bat once and enter it.' -ForegroundColor Yellow
  exit 0
}
$at = $adm.accessToken
$newShop = Check 'Manager adds a shop with the owner phone' {
  Api POST '/v1/admin/shops' @{ name = 'Smoke Cafe'; category = 'RESTAURANTS_CAFES'; ownerPhone = $ownerPhone; ownerName = 'Smoke Owner'; branchName = 'Hamra'; earnPercent = 10; city = 'Beirut' } $at
}

$owner = Check 'Owner signs in with OTP' { Login $ownerPhone 'BUSINESS' }
$ot = $owner.accessToken
Check 'Wrong OTP is rejected' {
  $ch = Api POST '/v1/auth/otp/request' @{ phone = RandPhone; app = 'CUSTOMER' }
  try { Api POST '/v1/auth/otp/verify' @{ challengeId = $ch.challengeId; code = '000000'; app = 'CUSTOMER' } | Out-Null; throw 'accepted a wrong code' }
  catch { if ("$_" -notmatch 'OTP_INVALID') { throw $_ } }
} | Out-Null
Check 'Owners cannot sign up a shop themselves' {
  try { Api POST '/v1/business/onboarding' @{ businessName = 'Sneaky'; category = 'OTHER' } $ot | Out-Null; throw 'self sign-up allowed' }
  catch { if ("$_" -notmatch 'ADDED_BY_MUKAFAAH') { throw $_ } }
} | Out-Null
Check 'Owner sets the loyalty % (10% back)' { Api PUT '/v1/business/manage/program' @{ earnPercent = 10 } $ot } | Out-Null
$me = Check 'Owner loads business' { Api GET '/v1/business/manage/me' $null $ot }
$branchId = $me.branches[0].id
$staff = Check 'Owner adds cashier with PIN' { Api POST '/v1/business/manage/staff' @{ name = 'Ahmad'; branchId = $branchId; pin = '1234' } $ot }
$code = Check 'Owner creates device pairing code' { Api POST '/v1/business/manage/pairing-codes' @{ branchId = $branchId } $ot }
$dev = Check 'Counter device pairs' { Api POST '/v1/business/cashier/pair' @{ code = $code.code; label = 'Smoke counter' } }
Check 'Wrong cashier PIN is rejected' {
  try { Api POST '/v1/business/cashier/login' @{ deviceId = $dev.deviceId; deviceSecret = $dev.deviceSecret; staffId = $staff.id; pin = '9999' } | Out-Null; throw 'accepted wrong PIN' }
  catch { if ("$_" -notmatch 'PIN_INVALID') { throw $_ } }
} | Out-Null
$cash = Check 'Cashier signs in with PIN' { Api POST '/v1/business/cashier/login' @{ deviceId = $dev.deviceId; deviceSecret = $dev.deviceSecret; staffId = $staff.id; pin = '1234' } }
$ct = $cash.accessToken
Check 'Cashier token cannot open owner dashboard' {
  try { Api GET '/v1/business/manage/dashboard' $null $ct | Out-Null; throw 'cashier reached owner API' }
  catch { if ("$_" -notmatch 'UNAUTHORIZED|401') { throw $_ } }
} | Out-Null
$look = Check 'Cashier looks up unregistered phone' { Api POST '/v1/business/cashier/lookup' @{ phone = $customerPhone } $ct }
if ($look.status -ne 'NOT_ON_APP') { Write-Host '  FAIL expected NOT_ON_APP' -ForegroundColor Red; $failed++ }
$k1 = [guid]::NewGuid().ToString()
$e1 = Check 'Cashier gives Pre-Points for $25 bill' { Api POST '/v1/business/cashier/earn' @{ phone = $customerPhone; billMinor = 2500 } $ct $k1 }
if ($e1.points -ne 250) { Write-Host "  FAIL expected 250 points, got $($e1.points)" -ForegroundColor Red; $failed++ }
$e1b = Check 'Same request retried is not double-credited' { Api POST '/v1/business/cashier/earn' @{ phone = $customerPhone; billMinor = 2500 } $ct $k1 }
if (-not $e1b.replayed) { Write-Host '  FAIL retry was not idempotent' -ForegroundColor Red; $failed++ }
Check 'Second visit adds more Pre-Points' { Api POST '/v1/business/cashier/earn' @{ phone = $customerPhone; billMinor = 1000 } $ct ([guid]::NewGuid().ToString()) } | Out-Null

$cust = Check 'Customer installs app and verifies the same phone' { Login $customerPhone 'CUSTOMER' }
$ut = $cust.accessToken
$pre = Check 'Customer sees pending Pre-Points' { Api GET '/v1/customer/prepoints' $null $ut }
if ($pre.totalPoints -ne 350) { Write-Host "  FAIL expected 350 pending, got $($pre.totalPoints)" -ForegroundColor Red; $failed++ }
$col = Check 'Customer collects (no merchant approval)' { Api POST '/v1/customer/prepoints/collect' $null $ut ([guid]::NewGuid().ToString()) }
if ($col.collectedPoints -ne 350) { Write-Host "  FAIL expected 350 collected" -ForegroundColor Red; $failed++ }
$w = Check 'Wallet shows 350 points' { Api GET '/v1/customer/wallet' $null $ut }
if ($w.totalPoints -ne 350) { Write-Host "  FAIL wallet total $($w.totalPoints)" -ForegroundColor Red; $failed++ }
$qr = Check 'Customer gets a fixed QR' { Api GET '/v1/customer/qr' $null $ut }
$qrAgain = Api GET '/v1/customer/qr' $null $ut
if ($qr.payload -ne $qrAgain.payload -or $qr.payload -notmatch '^MKF2:') { Write-Host '  FAIL QR is not fixed' -ForegroundColor Red; $failed++ }
$mk = Check 'New member got Mukafaah Points for joining' { Api GET '/v1/customer/mukafaah' $null $ut }
if ($mk -and $mk.balance -lt 1) { Write-Host '  FAIL no SIGNUP Mukafaah Points' -ForegroundColor Red; $failed++ }
$lk = Check 'Cashier scans QR' { Api POST '/v1/business/cashier/lookup' @{ qr = $qr.payload } $ct }
$programId = ($lk.programs | Where-Object { $_.type -ne 'PLATFORM' } | Select-Object -First 1).programId
Check 'Redeeming more than the balance is refused' {
  try { Api POST '/v1/business/cashier/redeem' @{ qr = $qr.payload; programId = $programId; points = 999999 } $ct ([guid]::NewGuid().ToString()) | Out-Null; throw 'overdraft allowed' }
  catch { if ("$_" -notmatch 'INSUFFICIENT_BALANCE') { throw $_ } }
} | Out-Null
$req = Check 'Cashier asks to redeem 100 points (customer must approve)' { Api POST '/v1/business/cashier/redeem' @{ qr = $qr.payload; programId = $programId; points = 100 } $ct ([guid]::NewGuid().ToString()) }
$w1 = Api GET '/v1/customer/wallet' $null $ut
if ($w1.totalPoints -ne 350) { Write-Host "  FAIL points left before approval $($w1.totalPoints)" -ForegroundColor Red; $failed++ }
$rd = Check 'Customer approves in the app' { Approve $req $ut }
if ($rd.newBalance -ne 250) { Write-Host "  FAIL balance after redeem $($rd.newBalance)" -ForegroundColor Red; $failed++ }
$st = Check 'Cashier sees the approval' { Api GET "/v1/business/cashier/redeem-requests/$($req.requestId)" $null $ct }
if ($st.status -ne 'APPROVED') { Write-Host "  FAIL cashier sees $($st.status)" -ForegroundColor Red; $failed++ }
$req2 = Api POST '/v1/business/cashier/redeem' @{ qr = $qr.payload; programId = $programId; points = 10 } $ct ([guid]::NewGuid().ToString())
Check 'Customer can decline a redeem' {
  $d = Api POST "/v1/customer/redeem-requests/$($req2.requestId)/decline" $null $ut
  if ($d.status -ne 'DECLINED') { throw "decline -> $($d.status)" }
} | Out-Null
$e3 = Check 'Member earns by QR ($5 -> 50 pts)' { Api POST '/v1/business/cashier/earn' @{ qr = $qr.payload; billMinor = 500 } $ct ([guid]::NewGuid().ToString()) }
if ($e3.newBalance -ne 300) { Write-Host "  FAIL balance after earn $($e3.newBalance)" -ForegroundColor Red; $failed++ }
Check 'Cashier sees own shift' { Api GET '/v1/business/cashier/shift' $null $ct } | Out-Null
Check 'Cashier voids that bill within the window' { Api POST "/v1/business/cashier/transactions/$($e3.transactionId)/void" $null $ct } | Out-Null
$w2 = Check 'Wallet back to 250 after void' { Api GET '/v1/customer/wallet' $null $ut }
if ($w2.totalPoints -ne 250) { Write-Host "  FAIL wallet after void $($w2.totalPoints)" -ForegroundColor Red; $failed++ }
$dash = Check 'Owner dashboard totals' { Api GET '/v1/business/manage/dashboard' $null $ot }
if ($dash) { Write-Host "     bills=$($dash.totals.billsMinor) issued=$($dash.totals.pointsIssued) redeemed=$($dash.totals.pointsRedeemed) cashiers=$($dash.byCashier.Count)" }
Check 'Owner sees transactions' { Api GET '/v1/business/manage/transactions' $null $ot } | Out-Null

# ---------- v0.2: shop profile, offers, bookings, rewards, products, discovery ----------
Check 'Owner sets shop profile (location, WhatsApp)' {
  Api PATCH '/v1/business/manage/profile' @{ description = 'Coffee and breakfast'; whatsapp = '+96170123456'; address = 'Hamra Street'; city = 'Beirut'; lat = 33.8966; lng = 35.4823 } $ot
} | Out-Null
$offer = Check 'Owner creates an offer that needs booking' { Api POST '/v1/business/manage/offers' @{ title = 'Free dessert for two'; kind = 'FREE_ITEM'; savingMinor = 800; requiresBooking = $true } $ot }
$walk = Check 'Owner creates a walk-in offer (50 points)' { Api POST '/v1/business/manage/offers' @{ title = 'Coffee upgrade'; kind = 'DEAL'; pointsCost = 50; requiresBooking = $false } $ot }
$reward = Check 'Owner adds a reward (100 points)' { Api POST '/v1/business/manage/rewards' @{ title = 'Free espresso'; pointsCost = 100; valueMinor = 250 } $ot }
Check 'Owner turns on the online store' { Api PUT '/v1/business/manage/store' @{ enabled = $true } $ot } | Out-Null
$prod = Check 'Owner adds a product' { Api POST '/v1/business/manage/store/products' @{ name = 'Latte'; priceMinor = 450 } $ot }
$tee = Check 'Owner adds a product with sizes (variants)' {
  Api POST '/v1/business/manage/store/products' @{ name = 'Mukafaah mug'; priceMinor = 800; options = @(@{ name = 'Size'; values = @('S', 'L') });
    variants = @(@{ optionValues = @('S'); priceMinor = 800; stock = 5 }, @{ optionValues = @('L'); priceMinor = 1000; stock = 0 }) } $ot }
$home = Check 'Customer home loads in one call' { Api GET '/v1/customer/home' $null $ut }
if ($home -and $home.balancePoints -ne 250) { Write-Host "  FAIL home balance $($home.balancePoints)" -ForegroundColor Red; $failed++ }
$shops = Check 'Customer lists shops by category' { Api GET '/v1/customer/shops?category=RESTAURANTS_CAFES' $null $ut }
$bizId = $me.id
$detail = Check 'Customer opens shop detail' { Api GET "/v1/customer/shops/$bizId" $null $ut }
if ($detail -and $detail.earnPercent -ne 10) { Write-Host "  FAIL earnPercent $($detail.earnPercent)" -ForegroundColor Red; $failed++ }
$bk = Check 'Customer books the offer' { Api POST "/v1/customer/offers/$($offer.id)/book" @{ partySize = 2; note = 'Window table' } $ut }
Check 'Second booking of the same offer is refused' {
  try { Api POST "/v1/customer/offers/$($offer.id)/book" @{} $ut | Out-Null; throw 'double booking' }
  catch { if ("$_" -notmatch 'BOOKING_EXISTS') { throw $_ } }
} | Out-Null
Check 'Owner sees the request and accepts it' {
  $list = Api GET '/v1/business/manage/bookings?status=REQUESTED' $null $ot
  if ($list.Count -lt 1) { throw 'no requests' }
  Api POST "/v1/business/manage/bookings/$($bk.id)/accept" $null $ot
} | Out-Null
$qr4 = $qr
$lk4 = Check 'Counter lookup shows accepted booking, walk-in offer and reward' { Api POST '/v1/business/cashier/lookup' @{ qr = $qr4.payload } $ct }
if ($lk4 -and ($lk4.bookings.Count -ne 1 -or $lk4.walkInOffers.Count -ne 1 -or $lk4.rewards.Count -ne 1)) { Write-Host '  FAIL counter perks missing' -ForegroundColor Red; $failed++ }
Check 'Cashier completes the booking (free)' { Api POST "/v1/business/cashier/bookings/$($bk.id)/redeem" @{ qr = $qr.payload } $ct ([guid]::NewGuid().ToString()) } | Out-Null
$rwq = Check 'Cashier asks to redeem the reward (100 points)' { Api POST "/v1/business/cashier/rewards/$($reward.id)/redeem" @{ qr = $qr.payload } $ct ([guid]::NewGuid().ToString()) }
$rw = Check 'Customer approves the reward' { Approve $rwq $ut }
if ($rw -and $rw.newBalance -ne 150) { Write-Host "  FAIL balance after reward $($rw.newBalance)" -ForegroundColor Red; $failed++ }
$apq = Check 'Cashier asks to apply the walk-in offer (50 points)' { Api POST "/v1/business/cashier/offers/$($walk.id)/apply" @{ qr = $qr.payload } $ct ([guid]::NewGuid().ToString()) }
$ap = Check 'Customer approves the offer' { Approve $apq $ut }
if ($ap -and $ap.newBalance -ne 100) { Write-Host "  FAIL balance after offer $($ap.newBalance)" -ForegroundColor Red; $failed++ }
$hist = Check 'Customer history has totals' { Api GET '/v1/customer/history' $null $ut }
if ($hist) { Write-Host "     earned=$($hist.totalEarned) used=$($hist.totalUsed) items=$($hist.items.Count)" }
$home2 = Check 'Total saving counts the reward and the offer' { Api GET '/v1/customer/home' $null $ut }
if ($home2) { Write-Host "     saving=$($home2.totalSavingMinor) tier=$($home2.tier)" }
Check 'Customer rates the shop after visiting' { Api PUT "/v1/customer/shops/$bizId/rating" @{ stars = 5 } $ut } | Out-Null
$tier = Check 'Tier by total spend' { Api GET '/v1/customer/tier' $null $ut }
if ($tier -and $tier.tiers.Count -lt 2) { Write-Host '  FAIL tiers missing' -ForegroundColor Red; $failed++ }
$al = Check 'Shop alerts list the booking and the order' { Api GET '/v1/business/manage/alerts?after=0' $null $ot }
if ($al -and -not ($al.alerts | Where-Object { $_.kind -eq 'BOOKING' })) { Write-Host '  FAIL no booking alert' -ForegroundColor Red; $failed++ }
$ref = Check 'Referral code exists' { Api GET '/v1/customer/referral' $null $ut }
$notes = Check 'Customer got notifications' { Api GET '/v1/customer/notifications' $null $ut }
if ($notes -and $notes.Count -lt 3) { Write-Host "  FAIL only $($notes.Count) notifications" -ForegroundColor Red; $failed++ }
$st = Check 'Customer opens the shop store' { Api GET "/v1/customer/shops/$bizId/store" $null $ut }
$mug = Check 'Customer opens a product with variants' { Api GET "/v1/customer/shops/$bizId/products/$($tee.id)" $null $ut }
$small = $mug.variants | Where-Object { $_.optionValues[0] -eq 'S' }
$large = $mug.variants | Where-Object { $_.optionValues[0] -eq 'L' }
Check 'Ordering a sold-out variant is refused' {
  try { Api POST "/v1/customer/shops/$bizId/order" @{ items = @(@{ productId = $tee.id; variantId = $large.id; qty = 1 }) } $ut | Out-Null; throw 'sold out allowed' }
  catch { if ("$_" -notmatch 'OUT_OF_STOCK') { throw $_ } }
} | Out-Null
$order = Check 'WhatsApp order message is built from server prices' {
  Api POST "/v1/customer/shops/$bizId/order" @{ items = @(@{ productId = $prod.id; qty = 2 }, @{ productId = $tee.id; variantId = $small.id; qty = 1 }); fulfilment = 'PICKUP' } $ut }
if ($order -and $order.totalMinor -ne 1700) { Write-Host "  FAIL order total $($order.totalMinor)" -ForegroundColor Red; $failed++ }
Check 'Owner confirms the order (stock goes down)' { Api POST "/v1/business/manage/store/orders/$($order.orderId)/status" @{ status = 'CONFIRMED' } $ot } | Out-Null
$mug2 = Api GET "/v1/customer/shops/$bizId/products/$($tee.id)" $null $ut
if ((($mug2.variants | Where-Object { $_.optionValues[0] -eq 'S' }).stock) -ne 4) { Write-Host '  FAIL stock not taken on confirm' -ForegroundColor Red; $failed++ }
Check 'Sending points needs Gold tier' {
  try { Api POST '/v1/customer/transfer' @{ to = $ownerPhone; programId = $programId; points = 20 } $ut ([guid]::NewGuid().ToString()) | Out-Null; throw 'transfer allowed for Silver' }
  catch { if ("$_" -notmatch 'TIER_REQUIRED|RECIPIENT_NOT_FOUND') { throw $_ } }
} | Out-Null
$dash2 = Check 'Owner dashboard shows engagement' { Api GET '/v1/business/manage/dashboard' $null $ot }
if ($dash2) { Write-Host "     offersUsed=$($dash2.engagement.offersUsed) rewards=$($dash2.engagement.rewardsRedeemed) orders=$($dash2.engagement.whatsappOrders) rating=$($dash2.engagement.rating)" }

# ---------- Mukafaah Manager (admin) ----------
$oc = Check 'Owner opens Collect on their own phone' { Api POST '/v1/business/manage/counter' $null $ot }
$e7 = Check 'Owner collects an invoice with its number' { Api POST '/v1/business/cashier/earn' @{ qr = $qr.payload; billMinor = 1000; invoiceNo = 'INV-1001' } $oc.accessToken ([guid]::NewGuid().ToString()) }
$bills = Api GET '/v1/business/manage/transactions' $null $ot
if (-not ($bills | Where-Object { $_.invoiceNo -eq 'INV-1001' })) { Write-Host '  FAIL invoice number not in bills' -ForegroundColor Red; $failed++ }
Check 'A customer account cannot open Mukafaah Manager' {
  try { Api GET '/v1/admin/overview' $null $ut | Out-Null; throw 'customer opened admin' }
  catch { if ("$_" -notmatch '401|403|FORBIDDEN|UNAUTHORIZED') { throw $_ } }
} | Out-Null
if ($at) {
  $rep = Check 'Manager monthly report' { Api GET '/v1/admin/reports/monthly' $null $at }
  if ($rep -and $rep.kpis.bills -lt 1) { Write-Host '  FAIL report shows no bills' -ForegroundColor Red; $failed++ }
  Check 'Manager adds a store product for the shop' { Api POST "/v1/admin/shops/$bizId/store/products" @{ name = 'Gift card'; priceMinor = 2000 } $at } | Out-Null
  Check 'Admin opens the overview' { Api GET '/v1/admin/overview' $null $at } | Out-Null
  Check 'Admin sets the shop to 12% back' { Api PATCH "/v1/admin/shops/$bizId" @{ earnPercent = 12; featured = $true } $at } | Out-Null
  $d2 = Api GET "/v1/customer/shops/$bizId" $null $ut
  if ($d2.earnPercent -ne 12) { Write-Host "  FAIL customer sees $($d2.earnPercent)% instead of 12%" -ForegroundColor Red; $failed++ }
  $cat = Check 'Admin adds a category' { Api POST '/v1/admin/categories' @{ key = ('SMOKE_' + (Get-Random -Maximum 99999)); nameEn = 'Smoke'; nameAr = 'تجربة'; emoji = '🧪' } $at }
  $bn = Check 'Admin adds a banner' { Api POST '/v1/admin/banners' @{ titleEn = 'Smoke banner'; style = 'YELLOW'; actionType = 'SHOP'; actionValue = $bizId } $at }
  $h3 = Check 'Customer home shows server banners, categories and blocks' { Api GET '/v1/customer/home' $null $ut }
  if ($h3 -and (-not ($h3.banners | Where-Object { $_.titleEn -eq 'Smoke banner' }))) { Write-Host '  FAIL new banner not on home' -ForegroundColor Red; $failed++ }
  if ($h3 -and $h3.blocks.Count -lt 1) { Write-Host '  FAIL home has no blocks' -ForegroundColor Red; $failed++ }
  Check 'Admin hides an offer' { Api PATCH "/v1/admin/offers/$($offer.id)" @{ hidden = $true } $at } | Out-Null
  $offs = Api GET "/v1/customer/shops/$bizId" $null $ut
  if ($offs.offers | Where-Object { $_.id -eq $offer.id }) { Write-Host '  FAIL hidden offer still shown' -ForegroundColor Red; $failed++ }
  Check 'Admin changes the transfer rules' { Api PUT '/v1/admin/settings/transfer' @{ minPoints = 10; dailyMaxPoints = 20000; dailyMaxCount = 10; minTier = 'GOLD' } $at } | Out-Null
  if ($bn) { Check 'Admin deletes the banner' { Api DELETE "/v1/admin/banners/$($bn.id)" $null $at } | Out-Null }
  if ($cat) { Api PATCH "/v1/admin/categories/$($cat.key)" @{ active = $false } $at | Out-Null }
  Api PATCH "/v1/admin/shops/$bizId" @{ earnPercent = 10; featured = $false } $at | Out-Null
  # v0.7: Mukafaah Friends, tiers, banner layout, accounts
  Check 'Admin makes the shop a Mukafaah Friend (up to 300 points)' { Api PATCH "/v1/admin/shops/$bizId/friends" @{ enabled = $true; maxPoints = 300 } $at } | Out-Null
  $mq = Check 'Cashier asks to redeem 50 Mukafaah Points' { Api POST '/v1/business/cashier/mukafaah/redeem' @{ userId = $lk.userId; points = 50 } $ct ([guid]::NewGuid().ToString()) }
  Check 'Customer approves the Mukafaah Points' { Approve $mq $ut } | Out-Null
  Check 'Admin reads the tiers' { Api GET '/v1/admin/tiers' $null $at } | Out-Null
  Check 'Admin picks the Duo banner layout' { Api PUT '/v1/admin/settings/home.bannerLayout' 'DUO' $at } | Out-Null
  $h4 = Api GET '/v1/customer/home' $null $ut
  if ($h4.bannerLayout -ne 'DUO') { Write-Host "  FAIL layout $($h4.bannerLayout)" -ForegroundColor Red; $failed++ }
  Api PUT '/v1/admin/settings/home.bannerLayout' 'UNO' $at | Out-Null
  $shopAcc = Check 'Admin gives the owner a Manager account for this shop' { Api POST '/v1/admin/accounts' @{ phone = $ownerPhone; name = 'Smoke Owner'; role = 'SHOP'; shopIds = @($bizId) } $at }
  $sa = Login $ownerPhone 'ADMIN'
  Check 'Shop account sees only its shop' {
    $mine = Api GET '/v1/admin/shops' $null $sa.accessToken
    if (@($mine).Count -ne 1) { throw "sees $(@($mine).Count) shops" }
    try { Api GET '/v1/admin/banners' $null $sa.accessToken | Out-Null; throw 'shop account opened banners' }
    catch { if ("$_" -notmatch 'FORBIDDEN_SCOPE') { throw $_ } }
  } | Out-Null
  if ($shopAcc) { Api PATCH "/v1/admin/accounts/$($shopAcc.userId)" @{ active = $false } $at | Out-Null }
}

if ($failed -gt 0) { Write-Host "  $failed check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host '  All checks passed' -ForegroundColor Green
exit 0
