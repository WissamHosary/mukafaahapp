# Adds sample shops (clearly marked "Demo") with offers, rewards and products
# through the real API, so the customer app has something to show while testing.
# Development only: it needs OTP_DEV_ECHO=true on the server.
param([string]$Base = 'http://localhost:3000', [string]$AdminPhone = '')
$ErrorActionPreference = 'Stop'
# Your Mukafaah Manager phone is remembered in tools\admin-phone.txt (this PC only).
$adminFile = Join-Path $PSScriptRoot 'admin-phone.txt'
if (-not $AdminPhone -and (Test-Path $adminFile)) { $AdminPhone = (Get-Content $adminFile -Raw).Trim() }

function Api($method, $path, $body = $null, $token = $null) {
  $headers = @{}
  if ($token) { $headers['Authorization'] = "Bearer $token" }
  $params = @{ Method = $method; Uri = "$Base$path"; Headers = $headers; ContentType = 'application/json; charset=utf-8'; TimeoutSec = 20 }
  if ($body -ne $null) { $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 6 -Compress)) }
  elseif ($method -ne 'GET') { $params['Body'] = [System.Text.Encoding]::UTF8.GetBytes('{}') }
  return Invoke-RestMethod @params
}
function RandPhone() { $p = @('70', '71', '76')[(Get-Random -Maximum 3)]; return $p + (Get-Random -Minimum 100000 -Maximum 999999) }
function Login($phone, $app = 'BUSINESS') {
  $ch = Api POST '/v1/auth/otp/request' @{ phone = $phone; app = $app; locale = 'en' }
  if (-not $ch.devCode) { throw 'devCode missing: the server must run with OTP_DEV_ECHO=true' }
  return (Api POST '/v1/auth/otp/verify' @{ challengeId = $ch.challengeId; code = $ch.devCode; app = $app }).accessToken
}

$shops = @(
  @{ name = 'Demo · Cedar Cafe'; cat = 'RESTAURANTS_CAFES'; earn = 10; city = 'Beirut'; address = 'Hamra'; lat = 33.8966; lng = 35.4823; about = 'Specialty coffee and breakfast all day.';
     offers = @(@{ title = 'Breakfast for two, dessert on us'; kind = 'FREE_ITEM'; savingMinor = 600; requiresBooking = $true }, @{ title = 'Size upgrade on any coffee'; kind = 'DEAL'; pointsCost = 50; requiresBooking = $false });
     rewards = @(@{ title = 'Free espresso'; pointsCost = 250; valueMinor = 250 }, @{ title = 'Free croissant'; pointsCost = 300; valueMinor = 300 });
     products = @(@{ name = 'Latte'; priceMinor = 450 }, @{ name = 'Manousheh zaatar'; priceMinor = 300 }, @{ name = 'Cheese croissant'; priceMinor = 350 }) },
  @{ name = 'Demo · Grill House'; cat = 'RESTAURANTS_CAFES'; earn = 8; city = 'Jounieh'; address = 'Old Souk'; lat = 33.9808; lng = 35.6178; about = 'Charcoal grills and family platters.';
     offers = @(@{ title = 'Family platter: 20% off'; kind = 'DISCOUNT'; discountPercent = 20; savingMinor = 700; requiresBooking = $true });
     rewards = @(@{ title = 'Free fries'; pointsCost = 200; valueMinor = 200 });
     products = @(@{ name = 'Mixed grill platter'; priceMinor = 2500 }, @{ name = 'Chicken taouk sandwich'; priceMinor = 500 }) },
  @{ name = 'Demo · Fresh Juice Bar'; cat = 'FOOD_DRINKS'; earn = 12; city = 'Beirut'; address = 'Achrafieh'; lat = 33.8869; lng = 35.5195; about = 'Fresh juices and cocktails.';
     offers = @(@{ title = 'Second juice half price'; kind = 'DEAL'; requiresBooking = $false });
     rewards = @(@{ title = 'Free large juice'; pointsCost = 400; valueMinor = 400 });
     products = @(@{ name = 'Avocado cocktail'; priceMinor = 600 }, @{ name = 'Orange juice'; priceMinor = 300 }) },
  @{ name = 'Demo · Iron Gym'; cat = 'FITNESS'; earn = 5; city = 'Tripoli'; address = 'Mina'; lat = 34.4367; lng = 35.8497; about = 'Gym, classes and personal training.';
     offers = @(@{ title = 'Free personal training session'; kind = 'SERVICE'; savingMinor = 2000; requiresBooking = $true });
     rewards = @(@{ title = 'One week pass'; pointsCost = 1500; valueMinor = 1500 });
     products = @() },
  @{ name = 'Demo · Glow Beauty'; cat = 'BEAUTY_WELLNESS'; earn = 10; city = 'Byblos'; address = 'Main Road'; lat = 34.1230; lng = 35.6519; about = 'Hair, nails and skin care.';
     offers = @(@{ title = 'Manicure + pedicure combo'; kind = 'DISCOUNT'; discountPercent = 15; savingMinor = 500; requiresBooking = $true });
     rewards = @(@{ title = 'Free hair wash'; pointsCost = 500; valueMinor = 500 });
     products = @() },
  @{ name = 'Demo · Toy Planet'; cat = 'GIFTS'; earn = 6; city = 'Saida'; address = 'Riad El Solh'; lat = 33.5571; lng = 35.3729; about = 'Toys and gifts for every age.';
     offers = @(@{ title = 'Free gift wrapping'; kind = 'FREE_ITEM'; requiresBooking = $false });
     rewards = @(@{ title = 'Puzzle 500 pieces'; pointsCost = 1200; valueMinor = 1200 });
     products = @(@{ name = 'Plush bear'; priceMinor = 1500 }) },
  @{ name = 'Demo · Atelier Boutique'; cat = 'FASHION'; earn = 8; city = 'Beirut'; address = 'Mar Mikhael'; lat = 33.8955; lng = 35.5236; about = 'Everyday clothing and accessories.';
     offers = @(@{ title = '15% off your first order'; kind = 'DISCOUNT'; discountPercent = 15; requiresBooking = $false });
     rewards = @(@{ title = 'Free tote bag'; pointsCost = 800; valueMinor = 800 });
     store = @(
       @{ cat = 'T-shirts'; name = 'Essential cotton tee'; description = 'Soft 100% cotton, regular fit.'; priceMinor = 1500; compareAtMinor = 1900;
          options = @(@{ name = 'Size'; values = @('S', 'M', 'L', 'XL') }, @{ name = 'Colour'; values = @('White', 'Black', 'Olive') }) },
       @{ cat = 'Hoodies'; name = 'Heavyweight hoodie'; description = 'Brushed fleece inside, kangaroo pocket.'; priceMinor = 3500;
          options = @(@{ name = 'Size'; values = @('S', 'M', 'L') }, @{ name = 'Colour'; values = @('Grey', 'Navy') }) },
       @{ cat = 'Accessories'; name = 'Canvas tote bag'; description = 'Fits a laptop. Inside pocket.'; priceMinor = 1200; options = @() }
     );
     products = @() }
)

if (-not $AdminPhone) { Write-Host 'Shops are added through Mukafaah Manager: run with your Manager phone number.' -ForegroundColor Red; exit 1 }
$at = Login $AdminPhone 'ADMIN'
Set-Content -Path $adminFile -Value $AdminPhone
$i = 0
$made = @()
foreach ($sh in $shops) {
  $i++
  try {
    $ownerPhone = RandPhone
    Api POST '/v1/admin/shops' @{ name = $sh.name; category = $sh.cat; ownerPhone = $ownerPhone; branchName = $sh.address; earnPercent = $sh.earn } $at | Out-Null
    $t = Login $ownerPhone
    Api PATCH '/v1/business/manage/profile' @{ description = $sh.about; city = $sh.city; address = $sh.address; lat = $sh.lat; lng = $sh.lng } $t | Out-Null
    $made += @{ id = (Api GET '/v1/business/manage/me' $null $t).id; earn = $sh.earn; featured = ($i -le 3) }
    foreach ($o in $sh.offers) { Api POST '/v1/business/manage/offers' $o $t | Out-Null }
    foreach ($r in $sh.rewards) { Api POST '/v1/business/manage/rewards' $r $t | Out-Null }
    # Online store: simple products, or products with options and one variant per combination.
    $items = @()
    foreach ($p in $sh.products) { $items += @{ name = $p.name; priceMinor = $p.priceMinor; options = @() } }
    if ($sh.store) { $items += $sh.store }
    if ($items.Count -gt 0) {
      Api PUT '/v1/business/manage/store' @{ enabled = $true } $t | Out-Null
      $cats = @{}
      foreach ($p in $items) {
        $body = @{ name = $p.name; priceMinor = $p.priceMinor }
        if ($p.description) { $body.description = $p.description }
        if ($p.compareAtMinor) { $body.compareAtMinor = $p.compareAtMinor }
        if ($p.cat) {
          if (-not $cats.ContainsKey($p.cat)) { $cats[$p.cat] = (Api POST '/v1/business/manage/store/categories' @{ name = $p.cat } $t).id }
          $body.categoryId = $cats[$p.cat]
        }
        if ($p.options -and $p.options.Count -gt 0) {
          $body.options = $p.options
          $combos = @(, @())
          foreach ($o in $p.options) { $next = @(); foreach ($c in $combos) { foreach ($v in $o.values) { $next += , ($c + $v) } }; $combos = $next }
          $body.variants = @(foreach ($c in $combos) { @{ optionValues = @($c); priceMinor = $p.priceMinor; stock = 10 } })
        }
        Api POST '/v1/business/manage/store/products' $body $t | Out-Null
      }
    }
    Write-Host "  OK   $($sh.name)" -ForegroundColor Green
  } catch {
    $msg = $_.Exception.Message
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
    Write-Host "  FAIL $($sh.name): $msg" -ForegroundColor Red
  }
}
# Points-back % and featured shops are set by Mukafaah Manager (admin).
if ($AdminPhone) {
  try {
    $at = Login $AdminPhone 'ADMIN'
    foreach ($m in $made) {
      Api PATCH "/v1/admin/shops/$($m.id)" @{ earnPercent = $m.earn; featured = $m.featured } $at | Out-Null
      # The featured demo shops also accept Mukafaah Points (Mukafaah Friends).
      if ($m.featured) { Api PATCH "/v1/admin/shops/$($m.id)/friends" @{ enabled = $true; maxPoints = 500 } $at | Out-Null }
    }
    Write-Host "  OK   points-back %, featured shops and Mukafaah Friends set as admin" -ForegroundColor Green
  } catch { Write-Host "  SKIP admin settings: $($_.Exception.Message)" -ForegroundColor Yellow }
} else {
  Write-Host '  Tip: run with -AdminPhone <your admin number> to also set each shop''s % and featured shops.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'Demo shops added. Open the customer app and pull down to refresh.'
