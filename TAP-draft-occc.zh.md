# TAP 草案：官方策展电路集合（Official Curated Circuit Collections，OCCC）— 中文版

> 本文是英文提案 `TAP-draft-occc.md` 的中文对照版，供阅读和讨论。按 TAP-01 的规定，提交时以英文版为准。

- 类型：Standards（标准）
- 依赖：TAP-02、ERC-165、ERC-721、ERC-1155、ERC-2981
- 状态：Draft（草案）
- 创建：2026-10-25
- 许可：CC0-1.0

## 一句话概述

让艺术家或项目方在 TapeOut 上发行一组固定的电路作品，并且任何人（买家、市场、其他合约）都能在链上查到：集合里哪些电路是真正的作品，哪些是别人塞进来的。

**给 TapeOut：** 本提案建议 TapeOut 做的两项升级（由每台处理器的创建者决定电路的元数据，所有项目都适用；以及创建者自愿把流片限定为只有自己能做）集中放在文末《给 TapeOut 的升级建议（重点）》。其他部分都不依赖它们。

## 摘要

在 TapeOut 上，一台处理器的电路合约就是一个 NFT 集合，但任何人都能往里加电路：有晶体管就能流片任意网表；一个晶体管都没有，也能用只含 REF 记录的网表零成本流片。

本提案定义**策展集合**（即标题中的官方策展电路集合，OCCC），也就是任何人都能核实其官方作品的集合：
- 发行在一笔交易里完成：一个 Vault 合约创建处理器，并把全部晶体管铸给自己。此后这个集合的晶体管只能经过 Vault 使用。
- Vault 只流片发行时用 Merkle 根固定下来的作品清单里的网表。
- 一个电路是**官方作品**，当且仅当它是 Vault 流片的，并且登记合约在同一笔交易里认证了它的编号。
- 策展人可以在清单里把部分作品标为**国库预留**，并在发行时写死国库地址：公众永远买不到这些作品，它们只能被领取进国库，之后国库可以像处理任何电路一样赠送或空投。

策展人还可以选择声明版税，供市场读取并可选择执行。每件官方电路都有一个官方编号，即它在本集合官方流片中的顺序。Vault 怎样销售作品（价格、顺序、作品怎样分配给买家、怎样付款）由 Vault 自己决定，只要遵守每个 Vault 都必须遵守的规则；官方身份与此无关。

本提案规定了登记合约的接口（`isOfficial`、`editionOf`、`tokenOf`、`serialOf`、`tokenOfSerial`、`isReserved`、`isCurated`、`collectionOf`、版税相关函数及事件）、登记合约在发行时必须检查的条件（包括必须由策展人本人发行）、每个 Vault 都必须遵守的规则、与链、登记合约和策展人绑定的作品清单叶子编码、必须公开全部叶子的要求、对集合名称、代号、介绍和作品标题的链上承诺、发行时固定的可选元数据目录（登记合约据此通过 `tokenURI` 为每件官方电路提供 ERC-721 元数据：名称、图片、属性），以及前端、市场和其他合约应该怎样使用这份记录。最后向 TapeOut 提出两项建议：由每台处理器的创建者决定电路的元数据；允许创建者把流片限定为只有自己能做。

## 动机

在 TapeOut 上，一个电路 NFT 集合就是一台处理器的全部电路。协议并不让处理器的创建者决定什么能进这个集合：

1. **任何持有晶体管的人都能把任意网表流片进去。** 如果晶体管是公开出售的，持有人就可以流片小玩具电路，或者流片一份和官方作品**一字不差**的网表。
2. **任何人都能不花晶体管，流片纯 REF 网表。** `tapeout` 只按网表自身的 NAND 和 LATCH 记录扣晶体管（TAP-02 §6），REF 记录不扣。一个只有一条 REF、指向官方电路的 31 字节网表，只需付流片费；它的 `circuitInfo`、`eval`、`step` 和官方电路完全相同（TAP-02 §4、§6）。

主网上的集合里已经出现了玩具电路和纯 REF 包装壳。2026-10-25 检查的两个集合里，有几十到约 1,400 个小玩具电路，以及几十到几百个纯 REF 包装壳，后者的 `circuitInfo` 与官方设计完全一致。项目方不承认这些电路，但市场照样把它们列在集合里，有的还标为“符合标准”。用户还反映，有晶体管持有人流片了与官方完全相同的网表，任何基于内容的检查都分辨不出来。

项目方判断“是不是官方”的真实依据，其实是链下掌握的“这个电路是谁流片的”。买家查不到，市场显示不了，给持有人发权益的合约也无法据此判断。本提案把这项信息变成链上公开、不可更改、含义固定的记录。

内容检查无法替代它：

| 类型 | 网表与正品相比 | 能否靠内容识别 |
|---|---|---|
| 玩具电路 | 不同 | 能，比对网表哈希 |
| 纯 REF 包装壳 | 字节不同，`circuitInfo` 和运行结果相同 | 只能比对网表字节 |
| 别人流片的同网表复制品 | 完全相同 | **不能** |

## 规范

（英文版中的 MUST / SHOULD / MAY 等关键词按 RFC 2119 / RFC 8174 解释。下文中“必须”“不得”“应当”“建议”“可以”分别对应 MUST、MUST NOT、SHOULD、RECOMMENDED、MAY。）

### 1. 术语

| 术语 | 含义 |
|---|---|
| 处理器合约 | 同 TAP-02：由 TapeOut 工厂创建的 ERC-721 合约，下文记作 `circuits` |
| 晶体管合约 | 处理器的 ERC-1155 合约；id 0 = NAND，id 1 = LATCH；两者共用一个供应上限 |
| 链 | 部署了 TapeOut 的链：撰写时有 BNB Smart Chain（链 ID 56）、X Layer（196）和 Base（8453）。“原生币”指该链自己的币（BNB、OKB、ETH） |
| 登记合约（Registry） | 实现第 3 节接口的合约，部署在一条链上，部署时绑定该链的 TapeOut 处理器工厂；没有所有者，不可升级 |
| Vault | 发行策展集合、并在登记合约里与之绑定的合约 |
| 策展集合 | 在登记合约里与某个 Vault 绑定的处理器合约 |
| 作品清单 | 由 `count` 件作品组成、编号从 0 开始的有序列表，用 Merkle 根承诺 |
| 官方电路 | 按第 2 节被登记合约认证的电路 `(circuits, tokenId)` |
| 策展人（Curator） | 发行集合的地址；是唯一可以领取预留作品的地址，并可以更换版税收款地址或调低比例 |
| 销售规则 | Vault 销售作品的方式（价格、顺序、作品怎样分配给买家、付款）；发行时固定，除第 6 节外不属于本标准 |
| 一组（Run） | 按顺序发售的作品清单里列一次、带有份数的一个设计，各份占连续的编号（第 5 节） |
| 支付资产 | Vault 为作品定价所用的原生币，或发行时固定的一种 ERC-20 代币（第 6 节第 8 条） |
| 官方编号（Serial） | 一件官方电路在本集合官方电路中按流片顺序的位置，从 1 开始（第 3 节） |
| 预留作品 | 作品清单标为国库预留的作品：不能被购买，只能被领取进国库 |
| 国库（Treasury） | 发行时固定的地址，接收所有预留作品 |

### 2. 官方电路的定义

电路 `(circuits, tokenId)` 在某个登记合约中是**官方的**，当且仅当：
1. `circuits` 是该登记合约中的策展集合（第 4 节）；
2. 该集合的 Vault 调用 `circuits.tapeout` 流片出了电路 `tokenId`；
3. 在同一笔交易里，Vault 对一个 `index < count`、此前未被认证过的作品调用了登记合约的 `certify(circuits, tokenId, index, netlistHash, reserved)`。

官方身份属于电路本身，而不是持有人：电路被转让、出售、赠送或空投后，官方身份都不变。

作品清单把同一个设计发行多份时（第 5 节），每一份都按同一条规则是官方作品，因为它是 Vault 流片的。任何其他人流片的同网表电路，无论在这台处理器上（只能是纯 REF 包装壳，见第 4 节）还是在别的处理器上，都不是官方作品。

不得根据网表字节、网表哈希、`circuitInfo`、运行结果、持有人或 tokenURI 来推断一个电路是否官方。

“官方”只相对于一台处理器而言。一位策展人可能发行多个集合，所以使用方必须以策展人公布的链 ID 和处理器地址来识别集合，而不能凭名称或代号（它们可以重复）。

### 3. 登记合约接口

登记合约必须实现以下函数和事件；表中除 `certify` 外均为只读函数：

| 函数 | 选择器 | 返回 |
|---|---|---|
| `isOfficial(address circuits, uint256 tokenId)` | `0x9a516edc` | 是否官方 |
| `editionOf(address circuits, uint256 tokenId)` | `0xe80e01aa` | `(是否官方, 作品编号)`；非官方返回 `(false, 0)` |
| `tokenOf(address circuits, uint256 index)` | `0xa3dabb02` | `(是否已流片, 电路 id)` |
| `isReserved(address circuits, uint256 tokenId)` | `0x9e9cf5c3` | 是否为清单预留给国库的官方作品；之后转手也不变 |
| `isCurated(address circuits)` | `0x774d70e4` | 是否为本登记合约中的策展集合 |
| `collectionOf(address circuits)` | `0x3e94c904` | `(vault, curator, transistors, treasury, root, count, reserved, certified, metadata, saleMode)`；`saleMode` 标识 Vault 的销售规则（由实现定义；0 = 按清单出售）；非策展集合全为 0 |
| `serialOf(address circuits, uint256 tokenId)` | `0x7be75877` | 该电路的官方编号（本集合第一件官方电路为 1，下一件为 2……）；非官方为 0 |
| `tokenOfSerial(address circuits, uint256 serial)` | `0x065b9385` | `(是否存在, 电路 id)`：该官方编号对应的电路 |
| `certify(address circuits, uint256 tokenId, uint256 index, bytes32 netlistHash, bool reserved)` | `0xaa92a7c0` | 不是只读函数：登记一件官方电路；只有该集合的 Vault 能调用（第 3 节第 4 条） |

| 事件 | Topic 0 |
|---|---|
| `CollectionLaunched(address indexed circuits, address indexed vault, address indexed curator, address transistors, bytes32 root, uint32 count, address treasury, uint32 reserved, bytes32 metadata)` | `0xfafcf03610954fd778b52f9044d3c3fcbade024c53f03257b287645a997bb10d` |
| `Certified(address indexed circuits, uint256 indexed tokenId, uint256 indexed index, bytes32 netlistHash, bool reserved)` | `0x8d7d8f5d2406ca80fb5e26889f1d3c94eaa0bc9e610a469ca59e18cab4ff1340` |
| `Serial(address indexed circuits, uint256 indexed tokenId, uint256 serial)` | `0x8299a793f3c0fd9c6e44cf13aa3d647c724f27561931bed2f30f320848a31a19` |

规则：
1. 每个 `circuits` 的 `CollectionLaunched` 必须恰好发出一次，并早于它的任何 `Certified`。
2. `Certified` 必须与该电路的流片在同一笔交易里发出，每个 `tokenId`、每个 `index` 各恰好一次。
3. `isOfficial` 一旦为真必须永远为真；`editionOf`、`tokenOf` 一旦设定不得改变；集合的 root、count、vault、curator、transistors、treasury、reserved、metadata 一旦设定不得改变。
4. 登记合约不得有所有者、管理员、暂停开关或升级机制，并且不得接受该集合 Vault 以外任何地址的认证。
5. 登记合约为一个集合认证的预留作品，不得超过发行时固定的 `reserved` 数量。
6. 每次认证必须分配下一个官方编号：一个集合第一件被认证的电路为 1，之后每件比上一件多 1。`Serial` 必须紧接 `Certified` 发出；`serialOf`、`tokenOfSerial` 一旦设定不得改变。

作品编号（`editionOf`）是作品在清单里的位置；官方编号（`serialOf`）是它在官方流片顺序中的位置，也就是持有人平常说的“#N”。登记合约要求发行时处理器是全新的（第 4.6 条），TapeOut 按流片顺序从 1 开始给电路编号，所以只要没有别人在这台处理器上流片，官方编号就等于 TapeOut 的电路编号。但任何人都能往任何处理器里流片纯 REF 包装壳（第 4 节），每个都会占用一个 TapeOut 编号，从那以后两种编号就会错开。现有合约下没有协议能阻止这一点，文末的建议二建议了能解决它的 TapeOut 改动。前端应当把官方编号显示为作品的编号，两者不同时在旁边显示 TapeOut 编号。按顺序发售的集合（第 5 节）里，官方编号等于作品编号加 1；随机把作品分配给买家时，官方编号是交付的顺序，与作品编号和标题无关。

### 4. 发行

登记合约必须仅在绑定时由它**自己在链上核实**以下全部条件都成立后，才把集合与 Vault 绑定（不能采信 Vault 的说法）：
1. 该 Vault 是本登记合约为这次发行创建的，所用的 Vault 代码在登记合约部署时就已固定（参考登记合约用 EIP-1167 克隆一个 Vault 实现合约，它的地址在登记合约里不可更改）；并且发起这次发行的正是策展人本人。登记合约不得发行策展人不是调用者的集合，这样谁也无法冒用艺术家的名义发行；
2. 登记合约所在链的 TapeOut 处理器工厂的 `isCPU(circuits)`（选择器 `0x5f5a364f`）为真；登记合约必须在部署时固定这个工厂；
3. `circuits.transistors() == transistors`，且 `transistors.circuits() == circuits`；
4. `transistors.creator() == vault`；
5. `transistors.minted() == transistors.supplyCap()`，且 `transistors.balanceOf(vault, 0) + transistors.balanceOf(vault, 1) == transistors.supplyCap()`；
6. 该处理器上还没有任何电路被流片（在已部署合约上，新处理器的 `nextId()` 返回 0，见“向后兼容”）；
7. 该处理器尚未被绑定。

创建处理器、把全部供应铸给 Vault、绑定，必须在同一笔交易里完成。由于处理器在这笔交易之前并不存在，其他任何人都不可能持有它的晶体管。

参考 Vault 在创建处理器之后立即调用它的 `restrictTapeoutToCreator()`（`0x9051fb27`），gas 上限 100,000，忽略结果。现有处理器没有这个函数，调用不会改变任何东西；如果 TapeOut 采纳文末的建议二，此后发行的集合从第一个区块起就只允许 Vault 流片，任何包装壳都塞不进来。

发行时必须设定销售结束时间，且它必须晚于发行时间。发行者应当写明愿意支付的工厂费和协议费上限；如果发行时读到的费用超过上限，发行必须回滚，防止在准备和发送发行交易之间费用被调高、吃掉发行者的余款。

发行时可以设置非零的铸造单价（例如为了满足前端展示门槛）。此时 Vault 付款给自己，并在每批之间用 `withdraw()` 收回；因为 Vault 就是创建者，实际成本只有工厂部署费和协议费。这部分“铸造收入”并不是真实需求，工具应当说明这一点。

### 5. 作品清单

每件作品是 `(index, netlist, nIn, nOut, price, reserved)`：netlist 是合法的 TAP-02 网表，price 是售价，以集合支付资产的最小单位计（原生币时为 wei；见第 6 节第 8 条），reserved 表示是否为国库预留。预留作品的 `price` 必须为 0。叶子为（伪代码，`abi.encode` 和 `keccak256` 与 Solidity 相同）：

```
leaf = keccak256(bytes.concat(keccak256(abi.encode(
    uint256 chainId, address registry, address curator,
    uint256 index, bytes32 keccak256(netlist), uint32 nIn, uint32 nOut, uint256 price, bool reserved))))
```

根按排序配对哈希计算，与 OpenZeppelin `MerkleProof` 的校验方式一致（`hash(a, b) = keccak256(a < b ? a ‖ b : b ‖ a)`）。叶子绑定了链、登记合约和策展人，所以作品清单不能被别人、在别的链或别的登记合约里重复使用。

因此，哪些作品公开发售、哪些作品国库预留，连同预留数量和国库地址，都在发行时就固定了。策展人事后不能把热门的公开作品挪进国库，买家在开售前就能看到全部预留作品。编号必须是 `0 … count − 1`，各用一次。

**同款多份。** 很多集合会把同一个设计卖很多次：几千个电路网表相同，每一个都是官方作品（第 2 节）。因此作品清单可以在多个编号上使用同一网表。工具应当拒绝同一网表出现两次的清单，除非策展人明确声明这是一个发行 `copies` 份的设计，工具会把它展开成 `copies` 个连续编号；没有声明的重复会被当作误传而拒绝。工具和公开格式应当只存一次这个设计，并记录份数，而不是每份存一遍。一个设计所需的晶体管按份数计算。

**按顺序发售。** 集合可以在发行时设为**按顺序发售**：作品严格按清单顺序出售，每次购买 Vault 都流片编号 `sold`（已流片的作品数）；作品清单由若干**组**组成，每组是一个设计的 `copies` 份相同作品，占编号 `first … first + copies − 1`（单件作品就是一份的一组），每组一片叶子：

```
runLeaf = keccak256(bytes.concat(keccak256(abi.encode(
    uint256 chainId, address registry, address curator, bytes32 keccak256("TAP-curated-run"),
    uint256 first, uint32 copies, bytes32 keccak256(netlist), uint32 nIn, uint32 nOut, uint256 price, bool reserved))))
```

标签和长度（11 个字）把组叶子与作品叶子区分开。由于谁也不能跳着买，作品在清单里固定的编号就是它的流片顺序，所以它的官方编号（第 3 节）是 `index + 1`；只要没有别人在这台处理器上流片，也就是它的 TapeOut 编号。这样项目方可以事先给作品编号（#1 是这个设计，#2 是那个）。按顺序发售的清单里，国库预留的组必须排在最前面，并在公开发售前按顺序领取（工具会检查）：排在中间的预留组会让发售停在那里直到领取，排在最后的则在发售结束仍未卖完时再也领取不到。发售结束时没卖出的作品总是清单末尾的那些，所以不会有官方编号被跳过。

**其他叶子格式。** Vault 可以用别的叶子格式承诺作品，例如流片前一直不公开的作品的叶子。这样的格式必须绑定链 ID、登记合约、策展人、每件作品的编号和网表哈希，必须带一个标签把它的叶子与上面的叶子区分开；叶子在开售前不公开时，还必须保证每个编号只能证明恰好一片叶子（按位置的树可以做到），这样谁也不能用偷加的第二片叶子。参考实现说明了它所用的格式。

Merkle 根承诺的是“一组叶子”，而不是“恰好 `count` 件作品”：不诚实的策展人可以给某个编号偷偷多加一片叶子（比如价格为 0），然后自己抢先买走。因此策展人必须在开售前公开全部叶子（每件作品的编号、网表、引脚数、价格和是否预留）；作品在流片前一直不公开的 Vault（这样谁也挑不了稀有作品），则必须在发售结束后立即公开，验证方应当用公开的清单重建根，并与 `collectionOf(circuits).root` 比对。公开清单重建不出链上根的集合，不得显示为已验证。

清单里的网表如果含 REF，必须指向在生成清单时已经存在、且引脚数一致的电路。指向尚不存在的编号，会让任何人抢先在那个编号上流片，从而决定官方作品的一部分行为；引脚数不对的 REF 则永远无法流片。

网表不需要与任何特定编辑器的编码结果一致，只需要合法，并且正是 Vault 将要流片的那串字节。

### 6. Vault

与集合绑定的 Vault：
1. 必须只流片其叶子能用 Merkle 证明对上根的网表，每个 `index` 最多一次；
2. 每次流片必须在同一笔交易里用 `tapeout` 返回的 id 调用 `certify`；
3. 不得出售预留作品；预留作品必须只流片给发行时固定的国库（国库不得是 Vault 或登记合约），总数不超过 `reserved`，并且只能在剩余晶体管被销毁（第 4 条）之前进行。进入国库后，预留作品就是一个普通电路，国库可以转让、赠送或空投，Vault 和登记合约对此不加任何限制；
4. 除了流片，以及在以下时机把剩余晶体管转入销毁地址以外，不得转移、授权或销毁晶体管：全部 `count` 件作品都已流片；或者销售已经结束，并且预留作品已全部领取、或者已过了 Vault 中固定的宽限期。销售结束时没卖出的公开作品永远不能再流片，宽限期也有上限，所以一件卖不出去的作品不会让剩余晶体管永远无法销毁；而策展人忘了领取的预留作品，不会在销售结束时就丢失；
5. 不得有所有者，也不得有在发行后修改根、数量、策展人、国库、预留数量，或发行时确定的价格和销售规则的函数。可以允许策展人暂停和恢复购买，并在销售尚未结束、Vault 尚未收尾时把销售结束时间往后推（不能提前）；不得允许任何人提前结束时间或重新打开已结束的销售；
6. 不得让发行者或任何人在发行交易内部购买作品（例如从退款回调里购买）；
7. 应当在流片的同一笔交易里把新电路转给买家；流片发生在之后的交易里时，必须把电路发给那一刻持有买家权利的人。
8. 可以用发行时固定的一种 ERC-20 代币（即支付资产）代替原生币为作品定价；TapeOut 的流片费和发行费仍用原生币支付。这样做的 Vault 必须能在链上读出这个代币，并且必须只在恰好收到该代币计的价格时才完成购买，这样谁都不会被记入没有到账的代币。
9. 按顺序发售的集合（第 5 节）里，每次购买和每次预留领取都必须恰好流片编号 `sold`，谁也不能不按顺序购买或领取。

除了这些规则，Vault 怎样销售由它自己决定，例如每件作品固定价格、预售，或者随机把作品分配给买家。这些都不影响官方身份，官方身份只由第 2 节决定。

### 7. 前端和市场

1. 前端若把某电路标为策展集合的官方或认证作品，必须依据其注明的、与该电路在同一条链上的登记合约的 `isOfficial`（或 `editionOf`）。前端必须用“链 ID + 地址”一起识别集合：一条链上的官方身份不代表另一条链上的任何事，同一个地址在另一条链上可能是另一台处理器（X Layer 和 Base 上 TapeOut 的合约地址相同）。
2. 不得依据 `circuitInfo`、运行结果、网表哈希、持有人或 tokenURI，把电路标为官方、认证或“符合标准”。
3. 对策展集合，应当明显标出非官方电路，并允许用户把它们过滤掉。
4. 应当把官方编号（`serialOf`）显示为作品的编号，同时显示作品编号（`editionOf`），TapeOut 电路编号与官方编号不同时也显示前者，并链接到认证交易（`Certified` 日志）。
5. 应当标明集合中哪些作品是国库预留（领取前后都标明，用 `isReserved`）；国库把预留作品转出后，仍必须显示为官方作品。
6. 只有当策展人公开的作品清单能重建出链上的根时（第 5 节），才应当把集合显示为已验证。
7. 不得把不是已认证电路的代币（例如 Vault 在作品流片之前发出的凭证或提货券）显示为电路或官方作品。
8. 应当按从 Vault 读出的集合支付资产（第 6 节第 8 条）显示价格，并使用该代币自己的 `decimals()`；作品以代币计价时，应当另外显示原生币的流片费。

### 8. 给持有人发放权益的合约

凡是根据策展集合电路的持有情况发放权益、奖励、访问权或投票权的合约，必须调用该集合登记合约的 `isOfficial(circuits, tokenId)` 进行校验，不得依赖网表内容或 `circuitInfo`。

### 9. 版税声明（可选）

TapeOut 的处理器合约没有实现 ERC-2981，策展人也无法给它加上。因此登记合约必须提供一个仅供参考的版税声明，格式照搬 ERC-2981，只多一个“处理器”参数；是否声明版税由策展人自行选择：

| 函数 / 事件 | 选择器 / Topic 0 | 含义 |
|---|---|---|
| `royaltyInfo(address circuits, uint256 tokenId, uint256 salePrice)` | `0x538bd5ea` | `(收款地址, 版税金额)`；电路不是官方作品、或集合没有声明版税时返回 `(address(0), 0)` |
| `royaltyOf(address circuits)` | `0xbb30d4ce` | 集合的 `(收款地址, 比例 bps)` |
| `setRoyalty(address circuits, address receiver, uint16 bps)` | `0x4adc6e44` | 仅策展人：更换收款地址或调低比例 |
| `RoyaltySet(address indexed circuits, address receiver, uint16 bps)` | `0x42467d290c72e182ef85378ad110bba52b9442ac5509a2fd4c2754a38dac93c9` | 发行时和每次修改时发出 |

1. 策展人可以在发行时声明版税（收款地址 + 比例，单位为万分之一），也可以不声明。当且仅当比例不为 0 时，必须给出收款地址；比例必须不超过 500（5%）。
2. 对非官方电路，`royaltyInfo` 必须返回 `(address(0), 0)`，所以 REF 包装壳和复制品永远搭不上集合的版税。
3. 发行后，策展人可以更换收款地址、可以调低比例，但比例不得调高；因此发行时没有声明版税的集合，之后也无法再加。其他任何人都不能修改。
4. 声明仅供参考。本提案不要求任何人支付，也不限制转账。市场应当为官方电路读取它，可以选择执行；市场可以在经由自己的交易中强制收取。

### 10. 元数据承诺

网表、价格和预留标记都由根（第 5 节）承诺，但集合名称、代号、介绍和作品标题不在任何叶子里。没有承诺的话，任何网站都可以给官方电路换上别的标题或介绍。因此登记合约在发行时为每个集合记录一个 `metadata` 值，通过 `collectionOf` 返回（伪代码）：

```
titlesHash = keccak256(abi.encodePacked(keccak256(bytes(title_0)), …, keccak256(bytes(title_{count−1}))))
metadata   = keccak256(abi.encode(keccak256("TAP-curated-metadata"),
                                  keccak256(bytes(name)), keccak256(bytes(symbol)), keccak256(bytes(story)),
                                  titlesHash))
```

所有字符串都按 UTF-8 编码，标题按编号顺序排列（每个编号一个标题；同一设计的每一份重复它的标题）。`name`、`symbol`、`story` 就是创建处理器时使用的字符串；参考登记合约在链上用发行参数计算它们的哈希（`metadataOf(name, symbol, story, titlesHash)`，`0xe2e2bef0`），因此承诺不可能与处理器不一致；发行者只需提供 `titlesHash`，且不得为 0。

1. `metadata` 必须在发行时固定，之后不得改变。
2. 策展人必须把名称、代号、介绍和全部标题与作品清单一起公开。
3. 前端应当先用这些内容重建 `metadata`，并与 `collectionOf(circuits).metadata` 比对，一致后才显示集合名称、代号、介绍和标题；不一致时不得把它们当作策展人发布的内容展示。

### 11. 代币元数据与图片（可选）

TapeOut 的处理器合约对每个电路的 `tokenURI` 都返回空值，也没有给处理器创建者留下设置它的入口，所以电路 NFT 在任何钱包和市场里都没有名称、图片和属性（文末的建议一请 TapeOut 让每台处理器的创建者来决定）。因此登记合约必须实现下列函数；策展人可以在发行时为集合记录一个**按内容寻址**的元数据目录，登记合约据此为官方电路提供 `tokenURI`：

| 函数 / 事件 | 选择器 / Topic 0 | 含义 |
|---|---|---|
| `tokenURI(address circuits, uint256 tokenId)` | `0xe9dc6375` | 官方电路如果 Vault 在流片时为它声明了自己的文件，就返回它，否则返回 `"<metadataURI>/<index>.json"`，`index` 是它在作品清单中的编号（`editionOf`）；非官方电路，或两者都没有时，返回 `""` |
| `metadataURIOf(address circuits)` | `0x9eac0ca2` | 集合的目录：`"ipfs://<CID>"`、`"ar://<交易 id>"` 或 `""` |
| `MetadataURISet(address indexed circuits, string uri)` | `0xf4ea916416710952791c00e6c397903c99c416633fd82eeb8f5786572a9d899c` | 只发出一次：在发行时，或作品先不公开的 Vault 公开作品时 |
| `TokenURISet(address indexed circuits, uint256 indexed tokenId, string uri)` | `0x7e2a04aa388921ad0859b09b5255b044773bb1782dd70ac3b1db0031e7fd054d` | Vault 在流片时为电路声明它自己的元数据文件时发出 |

1. 目录最多声明一次，之后不得改变：在发行时声明，或由作品在流片前不公开的 Vault 在公开作品时声明；从不声明目录的集合永远不会有目录。Vault 也可以改为在流片每件电路的交易里，为它声明一个内容寻址文件，只能声明一次（`declareTokenURI`，只有 Vault 能调用）。包括策展人在内，任何人事后都不能修改它们。
2. 目录必须按内容寻址，这样目录里的内容也无法改变：`"ipfs://"` 后接一个指向不可变内容的 CID（CIDv0：`Qm` 加 44 个 base58 字符；或以 `bafy` 或 `bafk` 开头的小写 base32 CIDv1（涵盖 dag-pb、dag-cbor 和 raw 类型，哈希算法不限），50 到 100 个字符；不带路径，不接受其他编码，也不接受指向 IPNS 记录的 libp2p-key CID），或 `"ar://"` 后接 43 个字符、至少含一个大写字母的 Arweave 交易 id（base64url，通常是一个 Arweave 路径清单的 id）。ArNS 名称和子名称都是小写，所以“必须含大写字母”这一条保证 43 个字符的名称永远不会被当成 id；随机 id 不含大写字母的概率约为 2 × 10⁻¹⁰，遇到时上传工具重新签名即可。可变的名称（IPNS、DNSLink、ENS、ArNS）和 `http(s)` 网址必须拒绝。参考实现的登记合约在链上检查（`isContentAddressed(bytes)`，`0x9bdfd89c`），不符合就让发行回滚。
3. 对非官方电路，`tokenURI` 必须返回 `""`，所以 REF 包装壳和复制品永远不会显示作品的图片。
4. 文件 `<index>.json` 应当遵循 ERC-721 元数据 JSON 格式（`name`、`description`、`image`，可选 `animation_url` 和 `attributes`）。其中 `name` 应当等于第 `index` 号作品已承诺的标题（第 10 节），`image` 和 `animation_url` 本身也应当按内容寻址（`ipfs://…` 或 `ar://…`，可以带路径，但路径每段只能有字母、数字和 `. _ ~ -`，不能是 `.` 或 `..`，也不能用百分号编码，这样链接无法跳出它的内容地址）。参考工具还会写入 `properties`，包含作品的 `index` 和 `netlistHash`，把图片和电路设计绑在一起。
5. 前端应当只通过登记合约的 `tokenURI` 读取电路的元数据，应当只显示按内容寻址的图片，并且不得把“有元数据”当作电路是官方作品的证据（第 7.2 条），这只由 `isOfficial` 决定。

因为目录在第一次销售前就已固定，策展人需要在发行前上传：先上传图片（每张图片各自得到一个内容地址），再为每件作品上传一个指向图片的 `<index>.json`，最后上传目录。发行时存储目录地址，比不存储多花约 90,000 gas（`ar://` id）到 105,000 gas（CIDv1），主网分叉实测。文件本身不存放在链上：Arweave 一次付费、永久保存；IPFS 需要至少一方（策展人、平台或持有人）持续保存（pin）这些文件，任何持有文件副本的人都能以同一个 CID 重新发布。图片由网表本身算出来的集合，也可以把 `animation_url` 指向一个存放在链上或 Arweave 上的渲染页面。

## 设计理由

- **看来历，不看内容。** 三类外来电路中，有两类除了原始网表字节以外，和官方电路在处理器合约的任何接口上都一样，其中一类连字节都一样。唯一能在所有情况下区分真假的，是“谁流片的”。在流片当下记录它，任何人都能读取，不必相信策展人事后的说法或某个索引服务。
- **为什么必须由策展人本人发行。** 对参考实现的内部复核发现：如果没有这条规则，任何人都能以真实艺术家的名义发行集合、复用艺术家的根，并让其中的电路被认证为官方。也可以用自己的名义复用艺术家的根。要求 `curator == msg.sender` 堵住了第一条路，把叶子绑定到策展人堵住了第二条。替艺术家操作发行的平台，仍可以让艺术家本人签署发行交易。
- **为什么预留作品在发行时固定。** 项目方常常要把一部分作品留给国库，以后用于赠送、空投或奖励贡献者。如果策展人可以事后决定留哪几件，就可能在看清需求后把最抢手的作品拿走。把预留标记写进叶子，并在发行时固定国库地址和预留数量，就让这个划分在任何人购买之前公开且不可更改。所有预留作品都先进入同一个固定的国库，而不是直接发给任意地址，这样国库的去向一目了然：之后的每一次赠送或空投都是一笔公开可查的普通转账。
- **为什么版税只是声明。** 电路的版税无法强制：NFT 合约属于 TapeOut，策展人既不能给它加 ERC-2981，也不能像 ERC-721C 那样限制转账，任何人都能绕开市场私下交易。整个 NFT 行业里，ERC-2981 本身也是出于同样的原因只作参考。一个公共协议能做的有用的事，是在市场本来就要读取的“官方认证”旁边，提供一个公开的位置写明策展人的条款，并保证在有人购买之后不能调高。实际收取交给市场。
- **为什么预留作品在销售结束后仍能领取。** 早先的版本在销售结束时就停止预留领取，策展人一旦忘了领取，作品就永久丢失。现在领取一直开放到剩余晶体管被销毁为止，而销毁只在还有预留作品未领取时才推迟，并且最多推迟一个固定的宽限期。这样既消除了这种损失，又不会让任何人把剩余晶体管永远留着不销毁。宽限期也没有给策展人新的权力：它只能把清单里本来就标为预留的作品，流片到发行时固定的国库。
- **为什么标题用哈希承诺。** 把每个标题都写进链上，要为只有前端才读的文字按字节付 gas。发行时固定一个哈希，只占一个存储槽，任何改动都能被发现。名称、代号和介绍由 Vault 用发行参数计算哈希，所以承诺描述的一定是实际创建的那台处理器。
- **为什么元数据用发行时固定的目录，而不是把图片存上链。** 对大多数集合来说，没有图的 NFT 用处不大；但在链上存图片每字节约 216 gas（在 BNB Smart Chain 上实测）：一个 700 KB 的动图约 1.5 亿 gas，几千件作品的集合要用掉数百个区块的 gas。按内容寻址的目录在链上只占一个短字符串，而它的地址本身就是目录里每个文件的哈希，所以承诺这个地址，就像根承诺网表一样牢固地承诺了目录里的每个文件，以及这些文件按内容地址链接的每张图片（第 11.4 条）。在发行时固定它，延续了本提案给买家的保证：买之前看到的东西，之后谁都换不掉，策展人也不行。拒绝可变名称，是因为名称只是一个指针，它的所有者可以改指向。对非官方电路返回 `""`，让图片和版税一样，跟着来历走，而不是跟着网表内容走。
- **为什么由 Vault 为它的处理器作答。** 处理器的创建者是 TapeOut 本来就和每台处理器关联的唯一一方，而策展集合的 Vault 按构造就是这个创建者（第 4.4 条）。让处理器去问创建者，TapeOut 就能支持所有策展集合以及将来的其他方案，而不必选择信任哪些登记合约。
- **为什么策展人可以暂停和延长销售，但不能缩短或重新打开。** 项目方在发售中可能遇到问题，比如页面故障、公告有误或市场突发事件，需要先停一停，或者多给买家一些时间。暂停和延长只改变“清单里的作品什么时候能买”：不增加作品、不改价格、不影响已售出的电路，买家得到的和当初承诺的完全一样。缩短销售或重新打开已结束的销售，会打破买家可以依赖的承诺：作品在公布的结束时间之前一直可以买，结束之后永远不再卖。所以这两种都做不到。
- **为什么每条链一个登记合约，不做跨链官方身份。** TapeOut 在每条链上各有一个工厂；处理器、它的晶体管和电路都只存在于一条链上（BEM 和矿机可以跨链，处理器和电路不能）。所以登记合约按链部署，并绑定该链的工厂，第 4 节的发行检查都针对集合所在的链。作品清单的叶子包含链 ID（第 5 节），为一条链生成的作品清单不能用在另一条链上，即使是同一个策展人、登记合约地址也相同。策展人想在多条链上发行同一批作品，就在每条链上各发行一个集合，每个集合只在自己的链上是官方的。如果一个登记合约接受来自其他链的认证，就需要跨链桥或预言机，也就不能再用一次只读调用核实了。
- **为什么策展人不能更换。** 发行后，包括策展人自己在内，任何人都不能更换策展人地址，私钥丢失也没有任何找回办法。任何找回途径都是一种可能被盗用或滥用的特权，买家还得去信任掌握它的人。担心单把私钥丢失的策展人，可以用多签钱包发行。
- **为什么由 Vault 流片，而不是买家自己流片。** 如果买家拿着分到的晶体管自己流片，登记合约就分不清他们的电路和用同样晶体管流片的复制品。晶体管全部留在 Vault 里，别人能流片进这台处理器的就只剩不消耗晶体管的纯 REF 网表，其中包括本身就是纯 REF 的清单作品的同字节复制品（见安全考虑）；它们都永远不会被认证。
- **为什么绑定时登记合约要自己全部重查。** 如果登记合约采信 Vault 的说法，那么保证的强度就只取决于最不严谨的那个 Vault。第 4 节的检查都是廉价的只读调用，能让发行保证不依赖 Vault 代码本身（前提是该 Vault 由本登记合约部署）。
- **为什么不做包装集合。** 包装集合（另发一个 ERC-721 包住官方电路）能让市场不接入也看到一个干净的集合，但它必须长期托管所有作品，风险集中；而且包装后电路归包装合约所有，买家会失去电路容器账户（ERC-6551）的控制权，在 TapeOut 上也不显示为持有人。登记合约什么资产都不持有。将来可以在这个登记合约之上再做可选的包装层。
- **为什么 Merkle 根在发行时固定。** 这样整份作品清单和每件作品的价格在第一次销售前就已经确定，策展人不能事后加作品，也不能悄悄把某个设计换成另一版。
- **为什么不要求与 tapeout.net 编辑器逐字节一致。** 官方身份来自被认证的流片，而不是重新推导网表。叶子承诺的就是 Vault 实际流片的字节。
- **为什么有官方编号，为什么要按顺序发售。** 持有人把作品叫作“#N”，大多数集合里，大家期望项目官网、市场和 TapeOut 上的 #N 是同一个电路。买家可以按任意顺序挑选作品时，清单编号不可能是这个数，因为 TapeOut 按流片顺序编号。所以登记合约把官方流片顺序记为官方编号，在有人塞进包装壳之前它都等于 TapeOut 编号；按顺序发售则让事先固定的清单编号等于这个顺序。用“组”表示同款多份，让最常见的项目形态（一个设计卖几千份）每个设计只需一片叶子，工具也只存一次设计。预留的组排在最前面，因为排在后面的预留组要么会卡住发售，要么在发售结束仍未卖完时再也领取不到。
- **为什么价格可以用代币计，而流片费仍用原生币。** TapeOut 上的社区常常想用自己的代币（例如 BEM）而不是链的原生币发售。TapeOut 的 `tapeout` 和 `createCPU` 用原生币收费，本提案无法改变，所以代币发售仍需要一小笔原生币；Vault 把两者分开（`msg.value` 恰好是流片费），两者不会被混淆。代币是一个发行参数，而不是登记合约里的一张名单，所以不需要任何人审批代币，某条链以后出现的代币也不用部署任何东西就能使用；代价是策展人可能选了行为异常的代币，但这只影响那一个集合（见安全考虑）。要求恰好收到全额，是因为转账扣费的代币会让 Vault 记入从未收到的代币。

## 向后兼容

本提案不修改任何 TapeOut 合约。已有的处理器无法按第 4 节成为策展集合，因为它们的晶体管已经流通。这些项目可以在另一个 TAP 里发布签名的官方编号名单，但那属于项目方的声明，不是来历保证，不在本提案范围内。

开发中在主网发现：`circuits.nextId()` 返回的是“到目前为止已流片的电路数”（新处理器返回 0；第一次流片后返回 1，该电路的 id 为 1），而不是 TAP-02 §6 所写的“下一个电路将获得的 id”。参考实现按 `nextId() == 0` 检查第 4.6 条。TAP-02 可能需要更正这一描述。

## 测试用例

参考实现包含 50 个 Foundry 测试（`test/Curated.t.sol` 48 个，`test/Copies.t.sol` 2 个），可以在 BNB Smart Chain、X Layer 或 Base 的主网分叉上运行（`forge test --fork-url https://bsc-dataseed.bnbchain.org`、`https://rpc.xlayer.tech` 或 `https://mainnet.base.org`），测试会自动选用该链的工厂和为该链生成的作品清单。作品清单是参考工具生成的 7 个临时测试电路：翻转触发器（toggle）、4 位计数器、7 位 LFSR、异或门、一件 REF 作品（在 BNB Smart Chain 上引用创世 13 号电路并加一位奇偶校验输出；在 X Layer 和 Base 上引用处理器 `0x0565EA48CA41Ae559d8d491dbb0a9ec945DB551b` 的 1 号电路并加一个取反输出），以及两件预留给国库的作品（TAP-02 测试向量 `popcount8_3151` 和一个使用中文标题的与门）。`test/Copies.t.sol` 使用同样电路组成的按顺序发售集合：两份预留的与门、五份翻转触发器和三份异或门（`copies`）。2026-11-01 在三条链上全部通过（BEM 测试只在 BNB Smart Chain 上运行，其他链上跳过），各条链上的合约完全相同；下面的 gas 和费用数字来自 BNB Smart Chain（免费公共节点只保留近期状态，所以测试分叉的是最新区块，而不是固定区块）。测试如下：

| 测试函数 | 测试 | 证明了什么 |
|---|---|---|
| `test_Launch_AtomicAndVerified` | 原子发行 | 一笔交易完成创建、铸完（非零单价，5 批）、绑定、锁定元数据目录、退回余款；183 万 gas（Vault 是克隆）；发行者实付正好是工具预测的工厂部署费和协议费，在 BNB Smart Chain 上共 0.0015 BNB（0.001 部署费 + 5 × 0.0001） |
| `test_Launch_ZeroMintPrice` | 零单价发行 | 单价为 0 时同样可行 |
| `test_Launch_RejectsBadParams` | 拒绝错误参数 | 无效的销售设置（例如销售结束时间不晚于开售时间）、发行资金不足 |
| `test_L2_LaunchFeeCap` | 发行费上限 | 费用超过发行者设定的上限时发行回滚 |
| `test_H1_CopycatLaunchRejected` | 拒绝冒名发行 | 任何人都不能以别人的名义发行；复用根、自任策展人的山寨集合卖不出清单里的任何作品 |
| `test_L3_RefundReentryBlocked` | 退款重入防护 | 策展人账户若在发行退款回调里尝试购买，会碰到重入保护（`ReentrancyGuardReentrantCall`），什么也买不到 |
| `test_L4_TokenOfAndEditionOfDefaults` | `tokenOf` 与 `editionOf` 的默认值 | 作品流片前，`tokenOf` 报告“未流片”（绝不会当成 id 0）；非官方电路返回 `(false, 0)`；流片后作品对应到它的电路 id |
| `test_TreasuryCannotBeVaultOrRegistry` | 国库不能是 Vault 或登记合约 | 国库既不能是正在创建的 Vault，也不能是登记合约 |
| `test_BuyAll_CertifyPayFinalize` | 全部售出 | 7 件作品都发出带网表哈希的 `Certified`、按正确编号认证、归买家所有（两件预留作品归国库）、网表字节与清单一致、晶体管消耗与工具预测完全相同；剩余 9,814 个 NAND 和 3 个 LATCH 被销毁 |
| `test_M1_FinalizeAfterSaleEnd` | 销售结束后收尾 | 销售结束后停止购买；还有预留作品未领取时，销毁要等宽限期结束，之后即使仍有作品未售也能销毁剩余晶体管 |
| `test_R1_NoWayToExtractTransistors` | R1 晶体管无法取出 | 任何人都无法转走、销毁或增发 Vault 的晶体管；售罄前且销售结束前无法收尾 |
| `test_R2_SameNetlistElsewhereIsNotOfficial` | R2 别处的同网表不算官方 | 同一网表在别的处理器上流片不是官方；在策展处理器上别人无法流片（`ERC1155InsufficientBalance`） |
| `test_R3_RefWrapperIsNotOfficial` | R3 REF 包装壳不算官方 | 陌生人零晶体管流片 REF 包装壳进入策展集合，`circuitInfo` 与官方相同，但不是官方 |
| `test_R4_EachWorkOnceAndStrictInputs` | R4 每件只铸一次，输入严格校验 | 重复购买、篡改网表、低价、错误证明、错误引脚数、把有效作品换到别的编号下、错误金额、越界编号、零接收地址 |
| `test_R5_OnlyBoundVaultCanCertify` | R5 只有绑定的 Vault 能认证 | 陌生人、非登记合约部署的 Vault 都无法绑定或认证（伪造的 Vault 两者都试过）；不能重复认证；编号不能越界 |
| `test_R7_WorkListIsFixed` | R7 清单不可改 | 根不可变；即使用真实的证明、编号和价格，清单外的网表也无法出售 |
| `test_SaleStartIsEnforced` | 开售时间 | 开售前无法购买 |
| `test_Sale_CuratorCanPauseAndResume` | 暂停与恢复 | 只有策展人能暂停；暂停期间谁都买不了，预留作品照常领取；恢复后可以继续购买 |
| `test_Sale_ExtendOnlyLaterWhileOpen` | 只能延长 | 只有策展人能延长；新的结束时间必须更晚；过了原结束时间仍可购买，收尾要等到新的结束时间；新的结束时间过后，既不能再延长，也不能重新开放 |
| `test_Sale_NoControlsAfterFinalize` | 收尾后不能再控制 | 收尾之后，既不能暂停，也不能延长 |
| `test_Royalty_OfficialOnly` | 版税只给官方作品 | 官方作品返回声明的 3% 版税；同集合里的 REF 包装壳返回 0 |
| `test_Royalty_None` | 不设版税 | 集合可以不声明版税，之后也无法再加 |
| `test_Royalty_CuratorCanOnlyLower` | 版税只能调低 | 策展人能换收款地址、调低比例；调高、陌生人修改、重复声明都会被拒绝 |
| `test_Royalty_ParamsChecked` | 版税参数校验 | 比例超过 5%、只有地址没有比例、只有比例没有地址，发行时都会被拒绝；正好 5% 可以发行 |
| `test_Reserved_PublicCannotBuy` | 预留作品不能购买 | 无论价格为 0 还是其他价格，都买不到预留作品 |
| `test_Reserved_CuratorClaimsToTreasury` | 策展人领取进国库 | 只有策展人能领取，开售前也可以；作品进入国库，是官方作品且标为预留，不产生收入，不能重复领取 |
| `test_Reserved_TreasuryCanTransferAndItStaysOfficial` | 国库转出后仍是官方 | 国库把作品送人、对方再转手，作品依然是官方作品且标为预留 |
| `test_Reserved_CannotClaimPublicWork` | 不能把公开作品挪进国库 | 策展人无法把公开作品领取进国库 |
| `test_Reserved_DeclaredCountIsACap` | 预留数量是上限 | 即使清单里藏了更多预留叶子，超过发行时声明的预留数量也领取不了 |
| `test_Reserved_Params` | 预留参数校验 | 有预留作品就必须设国库，国库不能是登记合约；预留数量不能超过作品总数 |
| `test_Reserved_ClaimAfterSaleEndWithinGrace` | 销售结束后仍可领取 | 销售结束后策展人仍能领取预留作品；还有未领取时，收尾要等到宽限期恰好结束；之后任何人都能收尾，收尾后不能再领取 |
| `test_Reserved_AllClaimedFinalizeAtSaleEnd` | 全部领取后立即收尾 | 预留作品全部领取后，销售结束时即可收尾，不必等待 |
| `test_Reserved_BatchClaim` | 一次领取多件 | 一笔交易把两件预留作品领取进国库；陌生人、总费用不对、混入公开作品（整批都不领取）、重复领取都会被拒绝 |
| `test_Metadata_Committed` | 元数据承诺 | 登记合约记录的承诺与工具计算的一致（含中文标题）；介绍不同则承诺不同；没有标题哈希时拒绝发行 |
| `test_Metadata_TokenURIOfficialOnly` | 只有官方作品有元数据 | 官方作品（购买的和预留的）返回 `<目录>/<编号>.json`；官方作品的 REF 包装壳、不存在的电路和其他处理器返回 `""`；作为处理器创建者的 Vault 通过 `circuitURI` 给出同样的答案，并通过 ERC-165 声明支持 `ICircuitURIProvider` |
| `test_Metadata_FixedAtLaunch` | 目录发行时固定 | Vault 和策展人都不能再次设置目录 |
| `test_Metadata_None` | 不设目录 | 发行时没有目录的集合，对所有电路返回 `""` |
| `test_Metadata_OnlyContentAddressed` | 只接受按内容寻址的目录 | `https` 网址、IPNS 名称（包括写成 base36 和 base32 CID 的 IPNS 密钥）、ENS 式域名、ArNS 名称、43 个字符的小写名称、带结尾斜杠的 CID、长度不对的 id、大写的 base32、非 base58 字符、大写的协议名都在发行时被拒绝；CIDv0、dag-pb 和 raw 类型的 CIDv1、Arweave id 被接受 |
| `test_L5_RejectsStrayFundsAndTokens` | 拒收意外资产 | Vault 拒收普通原生币，也拒收第三方转来的本处理器电路 |
| `test_ReentrancyFromRecipientFails` | 重入防护 | 接收方在回调里再次购买，会以 `ReentrancyGuardReentrantCall` 使整笔购买回滚 |
| `test_Token_BuyAndWithdraw` | 代币计价的购买 | 以 ERC-20 计价的集合里，买家用代币付价格，原生币只付流片费（用原生币付价格会被拒绝，没有授权的购买也会失败）；电路是官方作品；收入以代币付出，Vault 里不剩任何资产 |
| `test_Token_RefusesFeeOnTransfer` | 拒收转账扣费的代币 | 每次转账扣 1% 的代币以 `TokenAmountMismatch` 被拒绝，作品仍未售出 |
| `test_Token_FreeWorkAndParams` | 免费作品与参数检查 | 免费作品不需要授权；没有代码的地址不能作为支付代币，发行时被拒绝 |
| `test_Token_BEMOnBSC` | BSC 上的 BEM | 在 BNB Smart Chain 上，BEM（`0x5ce033B2bFCa3Af30b3e8C8457DeaF776A8b695a`，8 位小数）可以作为支付代币：没有转账税，收入以 BEM 付出（其他链上跳过） |
| `test_Token_NoReturnToken` | 无返回值的代币 | `transfer`、`transferFrom` 不返回值的代币（USDT 式）可以使用；登记合约不能作为支付代币 |
| `test_Token_FailedPayoutIsKept` | 代币付款失败的兜底 | 拉黑策展人的代币不会让购买失败；收入记入 `owed`，只有策展人能提到另一个地址 |
| `test_Clones_FixedImplementation` | 固定的实现合约 | 登记合约记有它的 Vault 实现合约；实现合约不能被初始化，已发行的 Vault 不能再次初始化，它的代码就是指向实现合约的 EIP-1167 代理 |
| `test_Token_ReentrantTokenIsBlocked` | 回调型代币被拦截 | 购买时回调 Vault 的代币会被重入保护拦下，不会多买 |
| `test_Copies_SoldInOrder_SerialEqualsTapeOutId` | 同款多份按顺序发售 | 预留组领取之前什么都卖不出；不按顺序的 `buy` 被拒绝；每一份都是官方作品，官方编号 = TapeOut 编号 = 清单编号 + 1；卖完的组不再出售 |
| `test_Copies_InjectedWrapperShiftsTapeOutIds` | 包装壳让编号错开 | 外人的 REF 包装壳占用一个 TapeOut 编号；下一件作品的官方编号比 TapeOut 编号小 1，包装壳没有官方编号 |

测试向量取自测试样例 `test/fixtures/manifest.json` 和 `copies.json`（链 id 56，登记合约 `0x00000000000000000000000000000000c0dec0de`，策展人 `0x00000000000000000000000000000000000c0ffe`），第 5、10、11 节的任何实现都必须得出相同的结果：

| 输入 | 期望输出 |
|---|---|
| 作品叶子（第 5 节）：index 0，netlistHash `0x7ca496e2d18c48a09aea26fc7df653df9c3fa5a10cb1a2bb7ec311c8220130b2`，nIn 1，nOut 1，price 10¹⁶ wei，reserved false | `0x14358d2386912617595812f5484d92d4899a96129a8904f771b29454b0524156` |
| 7 件作品的根（第 5 节） | `0x131d82b25cc3283cc417942e38b63e6d665024c75cc40c645602d13437af1949` |
| 7 个标题的 `titlesHash`（第 10 节） | `0x1ecdc691abff41d0c4b6f032dd9b4845349526520462790a1fcffac33215ba9a` |
| `metadata`（第 10 节）：名称 `P05 Test Collection`、代号 `P5TEST`、样例中的介绍和上面的 `titlesHash` | `0x131a0d4c42d02f4d670b1f463011bea1aa93a04665aaadcb1fe32dd663cd218c` |
| `isContentAddressed`（第 11 节）：`ipfs://QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG`、`ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi`、`ar://bNbA3TEQVL60xlgCcqdz4ZPHFZ711cZ3hmkpGttDt_U`、`""` | true |
| `isContentAddressed`（第 11 节）：`ipfs://k51qzi5uqu5dlvj2baxnqndepeb86cbk3ng7n3i46uzyxzyqj2xjonzllnv0v8`、`ar://myundername_mycollectionname-permaweb123456`、`https://example.com/meta` | false |
| 组叶子（第 5 节），样例 `copies.json`：first 2，copies 5，上面翻转触发器的 netlistHash，nIn 1，nOut 1，价格 10¹⁶ wei，非预留 | `0xf1ff4a2cd09c75999fb8275cc2685de0a3783c77a1ffeccf4b2dcc1cdb3b7569` |
| `copies.json` 的根（三组） | `0xbb2baad141cb47fc7d721f13b9d12728c769b088c543bc49affcba97c7d5095a` |

工具自检通过全部 13 个 TAP-02 向量（5 个合法、8 个非法）和 200 个随机画布设计；另外跑了 6,000 个随机设计（含输入、常量、LATCH 反馈、打乱文件顺序、多输出），编码后的网表与画布图在 8–24 拍内的运行结果全部一致。在本地分叉上按真实流程做了端到端演示：部署登记合约，针对它生成清单（链上检查 REF 目标），以策展人身份发行（`script/Demo.s.sol`），购买两件作品，一次领取两件预留作品，再由另一个账户流片一个 REF 包装壳。`curate verify` 报告两件作品为官方且网表一致，预留作品为官方、预留且归国库所有，包装壳为非官方——尽管它的 `circuitInfo` 完全相同；`curate checkroot` 用公开的作品重建出的根与链上一致，国库地址和预留数量也一致。

工具还会拒绝含有“指向尚不存在的电路”或“引脚数不对”的 REF 的清单，并对纯 REF 作品发出警告（任何人都能流片它的同字节复制品）。

## 参考实现

代码仓库：<https://github.com/gm-lsp/Tape-OCCC/tree/6d87cbc6c29acec5d39aae84ec9d05d6c006496f>（MIT）
- `src/CuratedRegistry.sol`：登记合约兼发行器（第 3、4 节）：检查发行参数，把每个 Vault 创建为构造时固定的 Vault 实现合约的克隆，记录官方电路、官方编号和元数据
- `src/CuratedTypes.sol`：发行参数
- `src/CuratedVault.sol`：参考 Vault（第 6 节）：每件作品固定价格，可任意顺序，也可按清单顺序出售同款多份；用原生币或一种 ERC-20 代币定价；收入付给策展人；国库预留、销售控制、收尾
- `src/interfaces/ICuratedRegistry.sol`：第 3、9、11 节的接口
- `src/interfaces/ICircuitURIProvider.sol`：建议一请 TapeOut 采用的接口
- `tool/curate.py`：无依赖的 Python 工具，内置每条链的 TapeOut 工厂：TapeOut 画布 → TAP-02 网表编码（用 TAP-02 参考实现校验）、链上检查 REF 目标、晶体管计数、作品清单和证明、元数据承诺和第 11 节的元数据文件（`metadata`）、发行清单与费用上限、重建根和元数据（`checkroot`）、链上验真（`verify`）
- `test/Curated.t.sol`、`test/Copies.t.sol`、`script/Demo.s.sol`：上述测试与演示；`script/Deploy.s.sol` 部署 Vault 实现合约和登记合约；`script/Launch.s.sol` 按清单发行集合（由 `script/ManifestParams.sol` 读取）

## 部署

尚未部署。

| 链（chainId） | 合约 | 地址 | 必须指向的实现 | 只读核对方式 | 已封存？ |
|---|---|---|---|---|---|
| BNB Smart Chain (56) | CuratedRegistry | 待定 | 不是代理合约 | `FACTORY()` 返回 `0x68224F668083c29e9800Be2a646d42d18cedF7e2`，且运行时字节码（屏蔽不可变量后）与所链接提交的参考实现一致 | 是（无所有者、无代理） |
| BNB Smart Chain (56) | CuratedVault | 上面登记合约的 `VAULT_IMPL()` | 不是代理合约；各 Vault 是它的 EIP-1167 克隆 | 运行时字节码与参考实现一致；不能被初始化 | 是（无所有者） |
| X Layer (196) | CuratedRegistry | 待定 | 不是代理合约 | `FACTORY()` 返回 `0x1f09DAeFA827f02CBb40967cc91b259763760761`，且运行时字节码（屏蔽不可变量后）与所链接提交的参考实现一致 | 是（无所有者、无代理） |
| X Layer (196) | CuratedVault | 上面登记合约的 `VAULT_IMPL()` | 不是代理合约；各 Vault 是它的 EIP-1167 克隆 | 运行时字节码与参考实现一致；不能被初始化 | 是（无所有者） |
| Base (8453) | CuratedRegistry | 待定 | 不是代理合约 | `FACTORY()` 返回 `0x1f09DAeFA827f02CBb40967cc91b259763760761`，且运行时字节码（屏蔽不可变量后）与所链接提交的参考实现一致 | 是（无所有者、无代理） |
| Base (8453) | CuratedVault | 上面登记合约的 `VAULT_IMPL()` | 不是代理合约；各 Vault 是它的 EIP-1167 克隆 | 运行时字节码与参考实现一致；不能被初始化 | 是（无所有者） |

TapeOut 工厂地址取自 TAP-10 的部署表。各链上登记合约的地址可能不同，前端按链注明登记合约（第 7.1 条）。参考实现的 `python3 tool/check_deploy.py --rpc <RPC> --registry <地址>`（在链接的提交上先 `forge build`）会做完这张表里的检查，并输出两个指纹：登记合约 `0x5ba3de9e9d56421bba8212612416ef0bf7181a03c3bc1edd0fe0565b1dbc01a2`，Vault 实现 `0x44b3b1d049a8cda1899cf42aa2354061def8331bb48989534229f851bbf64dd9`（运行时代码去掉末尾 CBOR 元数据后的 keccak256，登记合约的不可变量先置零）。

## 安全考虑

- **对 TapeOut 的信任。** 每条链上的工厂、处理器和晶体管合约都可被 TapeOut 多签分别升级；X Layer 和 Base 的工厂是与 BNB Smart Chain 分开的另一份部署（见 TAP-10）。分叉测试在三条链上都检验了下面这些行为。本提案依赖于：`isCPU` 正确；`tapeout` 只扣调用者的晶体管（晶体管合约有一个可由处理器合约调用的 `burnFrom`，所以升级后的处理器合约可以销毁 Vault 的库存）；供应上限不变；允许向销毁地址转账。登记合约的发行检查只在发行当时成立；已经做出的认证不受影响，因为它们记录的是流片当时的来历。
- **内部复核。** 对参考实现做过五轮内部安全复核，每轮都由未参与编写代码的人进行。第一轮：没有严重问题；1 个高危（冒用策展人名义发行，已用第 4.1 条和绑定策展人的叶子修复）；2 个中危（一件卖不出的作品让收尾永远无法进行；给某个编号偷加叶子——已用销售结束时间和第 5 节的公开要求修复）；5 个低危（已修复：`withdrawTo`、发行费上限、发行退款重入、`tokenOf` 不再依赖 id 0、拒收外来电路）。第二轮覆盖国库预留、版税和工具代码，没有严重问题；合约和工具方面的问题均已修复（其中包括：国库地址等于 Vault 或登记合约时拒绝发行；`checkroot` 改为重建全部作品，并逐项核对链上的全部发行设置）。第三轮对最终代码重新复核，没有严重、高危或中危问题；低危问题已修复，或列在下面（预留作品、国库合约、作品清单、销售结束时间）。第四轮复核元数据部分（第 11 节、建议一及工具的相应代码），没有严重问题，发现的问题都已修复：图片路径中用百分号编码的 `..` 可以跳出内容地址；写成 `ipfs://` CID 的 IPNS 密钥能通过检查；43 个字符的 ArNS 子名称理论上可能被当成 Arweave id（现在由“必须含大写字母”一条排除）；工具发行前没有把目录读回核对；元数据文件并非在所有平台上都按 UTF-8 写入。第五轮复核按清单顺序出售同款多份、收入直接付出和克隆，没有严重问题；发现的问题都已修复。每一项链上修复都有回归测试；第一轮“偷加叶子”的问题由第 5 节的公开要求处理，`checkroot` 会执行这项检查。
- **元数据的可用性。** 登记合约固定的是元数据的地址，而不是它能否被访问。IPFS 上的文件如果没有人保存，就会消失；策展人最好在多个服务商处保存，或使用 Arweave。通过 HTTP 网关读取文件的前端，相信网关返回的就是地址所对应的内容；前端可以自行用地址核对内容。发行时目录无法访问或写错的集合，事后无法更正（§11.1），所以工具最好在发行前把目录读回来核对。
- **“官方”不保证什么。** 登记合约认证的是电路的来历，而不是它的功能。策展人可以列入任何合法网表，包括引用其他处理器电路的网表，其行为取决于被引用的电路（TAP-02 安全考虑）。
- **外来电路仍会出现在集合里。** 纯 REF 包装壳永远可以流片进任何处理器。本提案让它们可以被区分，但无法也不试图阻止它们。不遵守第 7 节的前端仍会显示它们。
- **Vault 的资产。** Vault 持有的晶体管只能用于它自己的处理器，以及它的销售规则留待以后使用的资金（例如尚未用掉的费用，或没能付出去的款项）。Vault 没有所有者。每次销售和领取都先更新 Vault 的状态，再进行外部调用；所有会进行外部调用、修改状态的入口共用同一个重入保护。
- **合约买家与 EIP-7702 账户。** 用 `safeTransferFrom` 发送电路时，如果接收方有代码但没有实现 `onERC721Received`，购买会整体回滚，不会损失资金；买家可以指定另一个接收地址。在之后的交易里交付电路的 Vault 应当用普通的 `transferFrom` 发送，这样持有人无法阻挡其他人的交付；不能处理 ERC-721 的持有人合约会收到一个它转不出去的电路，这是买家自己选择的接收地址。注意 BNB Smart Chain 和 Base 上一些广为人知的地址带有 EIP-7702 委托代码。
- **先到先得。** 网表和证明在开售前公开时，开售后机器人可以立刻抢走 0 元或低价作品；两人也可能同时抢同一件，后到的交易回滚。Vault 可以让作品在流片前一直不公开（第 5 节），从而避免这一点。
- **预留作品。** 国库像持有普通电路一样持有预留作品，保护它们的是国库的私钥，建议使用多签钱包。预留作品可以一直领取到剩余晶体管被销毁为止：销售结束后，如果预留作品已全部领取，或者已过 `RESERVE_GRACE`，任何人都可以调用 `finalize` 销毁；到那时还没领取的预留作品会永久丢失。
- **国库合约。** 预留作品用 `safeTransferFrom` 发给国库。如果国库是一个不接收 ERC-721 的合约，每次领取都会回滚，收尾后这些预留作品就丢失了。Safe 等多签钱包可以接收；策展人最好在发行后立即领取一件预留作品来确认。
- **作品清单。** 作品叶子绑定的是链、登记合约和策展人，而不是某一个集合。策展人如果在第二个集合里重复使用同一份作品清单，每份证明在两个集合里都有效；工具最好为每个集合生成新的清单，前端以链 ID 和处理器地址识别集合，绝不用名称。
- **销售结束时间。** 销售结束前，未售出的作品都可以购买，剩余晶体管也一直留在 Vault 里。如果结束时间非常遥远（测试样例用的是 2100 年），剩余晶体管实际上永远不会被销毁；策展人最好设定合理的结束时间。
- **支付代币。** 代币由策展人选择，登记合约不做审核。代币可能被暂停、把 Vault 或某个买家列入黑名单、被升级成别的行为，或者回调买家；这时该集合的购买可能失败。官方身份、已售作品、作品清单和其他集合都不受影响。在购买之外直接转进 Vault 的代币无法拒收、也无法取回，会一直锁在里面（原生币则会被 `receive` 拒收）。每次购买都有重入保护，并先更新状态再进行外部调用；恰好收到全额的检查会拒绝少于价格到账的代币。比实际需要更大的授权也只允许这个没有所有者的 Vault 扣款，而且只在授权人自己发起的购买中。前端最好显示集合使用的代币，并在用陌生代币购买前提醒。
- **销售控制。** 策展人可以无限期暂停购买，也可以不断把结束时间往后推，这同时会推迟收尾和剩余晶体管的销毁。暂停期间买家无法强行购买；拿到策展人私钥的攻击者可以暂停或延长销售，但拿不走收入、改不了价格、也加不了作品。持有人和已售作品的官方身份永远不受影响。前端应当读取 `paused()` 和当前的 `SALE_END()`，而不是发行时的值。
- **策展人私钥。** 策展人地址永远不能更换。私钥一旦丢失，未领取的预留作品无法再领取，版税无法再修改，Vault 交给策展人的其他操作也都无法再做。这是有意的设计（见设计理由）；建议策展人使用多签。
- **纯 REF 作品。** 只由 REF 记录组成的作品不消耗晶体管，任何人都能把它的同字节复制品流片进策展处理器。复制品不是官方的，但看起来一样；工具会对这类作品发出警告。
- **费用变化。** Vault 在流片时读取 `TAPEOUT_FEE()`，费用变化会被转嫁，而不会导致无法销售。
- **网表大小。** BNB Smart Chain 主网上超过约 34,000 字节的流片会失败（其他链的区块 gas 上限可能不同），工具会拒绝。大作品应拆成子电路，再用 REF 组合。
- **Merkle 叶子**做了双重哈希，内部节点无法被冒充为叶子。
- **尚未审计。** 参考实现只做过内部复核。在独立审计之前，不宜用于承载大额资产。

## 给 TapeOut 的升级建议（重点）

**这是本提案请 TapeOut 考虑的两项升级。** 它们是建议，不是本标准的要求：本提案的其他部分都不依赖它们，在现有合约上全部可用。两项都只需对 TapeOut 信标背后的共用处理器实现各做一处改动，都由创建者自愿选用，创建者什么都不做的处理器没有任何变化。参考 Vault 已经为两项都做好了准备，所以今天发行的集合会在 TapeOut 采纳的那一刻直接受益。

### ★ 建议一（重点）：由每台处理器的创建者决定其电路的元数据

**我们请求的改动。** 目前处理器对每件电路的 `tokenURI` 都返回空，也不给创建者任何设置的办法，所以任何电路在钱包和市场里都没有名称和图片。TapeOut 只需对信标背后的共用处理器实现做一处改动，**所有项目，不论是否使用本提案**，都能让自己的电路在任何地方显示元数据。规则只有一条：**电路显示什么，由处理器的创建者决定。** `tokenURI(id)` 依次这样回答：

1. **创建者设置的目录。** 创建者调用一次 `setCircuitBaseURI(uri)`，之后第 `id` 号电路显示 `"<uri><id>.json"`。所有用普通钱包创建处理器的项目都适用，包括升级前就创建好的处理器（升级后创建者设置一次即可）。可选：创建处理器的函数也可以直接带上这个目录参数，项目方在创建时就设好。
2. **自己会回答的创建者合约。** 没有设置目录、而创建者是一个通过 ERC-165 声明了 `ICircuitURIProvider` 的合约时，处理器用 `circuitURI(circuits, tokenId)` 去问它。策展集合走的就是这一条：它们的创建者是 Vault，Vault 没有所有者，永远不能调用设置函数，它返回登记合约的 `tokenURI`（只限官方作品，发行时固定）。
3. **两样都没有：** 返回 `""`，即现在的行为；什么都不做的项目没有任何变化。

**必须照做的细节。** 第 2 条必须正好使用这个接口：`circuitURI(address,uint256)`，接口号 `0xcd51078c`。Vault 的代码在集合发行时就固定了；参考 Vault 已经实现了这个接口和 ERC-165，所以只要名称一致，所有已经发行的策展集合会在升级生效的那一刻自动显示元数据，不需要任何操作。

示例（说明性）：

```solidity
interface ICircuitURIProvider {
    function circuitURI(address circuits, uint256 tokenId) external view returns (string memory); // 0xcd51078c
}

string public circuitBaseURI;                               // 0x3e3f2de4
event CircuitBaseURISet(string uri);

/// Only the processor's creator (an ordinary wallet or a contract) may set it.
function setCircuitBaseURI(string calldata uri) external {  // 0x8651a9c5
    require(msg.sender == transistors.creator());
    circuitBaseURI = uri;
    emit CircuitBaseURISet(uri);
}

function tokenURI(uint256 id) public view returns (string memory) {
    _requireOwned(id);
    // 1. a directory set by the creator
    if (bytes(circuitBaseURI).length != 0) return string.concat(circuitBaseURI, Strings.toString(id), ".json");
    // 2. a creator contract that answers itself (low-level calls: try/catch would not catch bad return data)
    address creator = transistors.creator();
    if (creator.code.length == 0) return "";
    (bool ok, bytes memory r) = creator.staticcall{gas: 30_000}(
        abi.encodeCall(IERC165.supportsInterface, (type(ICircuitURIProvider).interfaceId)));
    if (!ok || r.length < 32 || abi.decode(r, (uint256)) != 1) return "";
    (ok, r) = creator.staticcall{gas: 200_000}(abi.encodeCall(ICircuitURIProvider.circuitURI, (address(this), id)));
    if (!ok || r.length < 64) return "";
    (uint256 offset, uint256 length) = abi.decode(r, (uint256, uint256));
    if (offset != 32 || length > r.length - 64) return "";
    return abi.decode(r, (string));
    // 3. neither: "" (today's behaviour)
}
```

对 TapeOut 来说为什么安全：处理器只询问它自己的创建者，而创建者在处理器创建时就固定了，所以 TapeOut 不需要给登记合约设白名单，也不需要评判任何集合。gas 上限防止有问题的创建者合约让 `tokenURI` 变得昂贵；任何失败（调用回滚、gas 用尽、返回数据过短或格式不对）都返回 `""`。正式实现还应最多复制几 KB 的返回数据（用汇编，因为普通 `staticcall` 会复制全部）。创建者设置的目录对这台处理器的所有电路都生效；策展 Vault 只为官方作品回答，所以塞进策展处理器的 REF 包装壳和复制品永远不会显示作品的图片（第 11 节）。

### ★ 建议二（重点）：允许处理器的创建者把流片限定为只有自己能做

任何人都可以不用晶体管往任何处理器里流片纯 REF 包装壳（第 4 节、动机）。包装壳永远不是官方作品，但它们出现在集合的合约里，看起来像作品，还会占用 TapeOut 的电路编号，所以第一个包装壳出现之后，后面作品的官方编号（第 3 节）和 TapeOut 编号就会错开。基于现有处理器的任何协议都无法阻止这一点。TapeOut 可以让创建者选择把处理器设为只有创建者能流片：

```solidity
bool public tapeoutRestricted;                          // 只读，默认 false
event TapeoutRestricted();

/// 单向：一旦设置，永远不能撤销。
function restrictTapeoutToCreator() external {           // 0x9051fb27
    require(msg.sender == transistors.creator());
    tapeoutRestricted = true;
    emit TapeoutRestricted();
}

// 在 tapeout(...) 开头：
//     if (tapeoutRestricted && msg.sender != transistors.creator()) revert NotCreator();
```

策展集合的创建者是它的 Vault，所以改动之后，处理器里只可能出现官方作品，官方编号也永远等于 TapeOut 编号。评估：这项改动只涉及“谁能在一台处理器里创建电路”。它不影响没有选择开启的处理器（默认关闭），不影响已有电路，也不影响 REF：受限处理器的电路仍然可以被其他处理器当作 REF 目标，读取电路的功能（运行、挖矿、REF 解析、ERC-6551 账户）都不需要知道这项设置。它必须是单向的，否则创建者可以在买家依赖它之后再解除限制。普通钱包作为创建者也可以限制自己的处理器，这是它自己的选择，只影响它自己的集合。参考 Vault 已经在创建处理器后立即调用 `restrictTapeoutToCreator()`（第 4 节，限制 gas 并忽略失败），所以只要 TapeOut 以这个选择器和这个含义采纳改动，此后发行的每个集合从第一个区块起就是受限的，不需要新的登记合约。

## 版权

依 [CC0](../LICENSE) 放弃版权及相关权利。
