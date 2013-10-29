/*
This script creates all of the CLR related objects.
It also does what's necessary in order to run a CLR object.
*/
if exists (select * from sys.configurations where name = 'clr enabled' and value = 0)
begin
	EXEC sp_configure 'clr enabled', 1
	RECONFIGURE WITH OVERRIDE
end
GO
USE db_cdba
GO
IF schema_id('SYL') IS NULL
	EXEC('CREATE SCHEMA SYL')
GO
/*
This part runs in order to allow the registering of an unsafe assembly.
I know unsafe sounds pretty, well... unsafe, but that's what you have
to register the assembly as, in order to allow it to do what it does.
*/
ALTER DATABASE db_cdba SET TRUSTWORTHY ON
ALTER AUTHORIZATION on database::db_cdba to sa
GO
if OBJECT_ID('SYL.udf_EncryptPassword') is not null
	drop function SYL.udf_EncryptPassword
GO
if OBJECT_ID('SYL.usp_RunCommand') is not null
	drop procedure SYL.usp_RunCommand
GO
if exists (select * from sys.assemblies where name = 'SYL')
	drop assembly SYL
GO
CREATE ASSEMBLY [SYL]
FROM 0x4D5A90000300000004000000FFFF0000B800000000000000400000000000000000000000000000000000000000000000000000000000000000000000800000000E1FBA0E00B409CD21B8014CCD21546869732070726F6772616D2063616E6E6F742062652072756E20696E20444F53206D6F64652E0D0D0A2400000000000000504500004C010300FC10B24F0000000000000000E00002210B01080000320000000A0000000000002E50000000200000006000000000400000200000000200000400000000000000040000000000000000A000000002000000000000020040850000100000100000000010000010000000000000100000000000000000000000D44F00005700000000600000E007000000000000000000000000000000000000008000000C00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000080000000000000000000000082000004800000000000000000000002E7465787400000034300000002000000032000000020000000000000000000000000000200000602E72737263000000E0070000006000000008000000340000000000000000000000000000400000402E72656C6F6300000C0000000080000000020000003C0000000000000000000000000000400000420000000000000000000000000000000010500000000000004800000002000500EC310000E81D000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001E02280100000A2A1B3003006000000001000011730200000A0B070D09026F0300000A090E046F0400000A090316FE0116FE016F0500000A096F0600000A2D0E09046F0700000A09056F0800000A0972010000706F0900000A09166F0A00000A096F0B00000A0ADE0925280C00000A0C087A062A010C0000000006004F5500090A0000011B300300A200000002000011730E00000A0B076F0F00000A8C0F000001281000000A0C026F1100000A721300007016281200000A16330907176F1300000A2B67026F1100000A722F00007016281200000A16330A071F0C6F1300000A2B4908026F1400000A2C190708026F1500000A6F1600000A281700000A6F1300000A2B270708026F1500000A6F1600000A281700000A6F1300000ADE0E25280C00000A0D280D00000ADE00076F1800000A2A0000010C000000007400198D000E0A0000011B300500F900000003000011731900000A0D026F1A00000A6F1B00000A130538BB00000011056F1C00000A7414000001130411046F1D00000A28030000060A0617FE01061DFE0160061F0BFE0160061F0CFE0160061F12FE0160061F1DFE0160061F15FE0160061F16FE0160061F17FE0160061F19FE01602C4511046F1E00000A11046F1D00000A280300000611046F1F00000A20A00F0000FE02158C1800000111046F1F00000A8C18000001282000000A282100000A732200000A0C2B1911046F1E00000A11046F1D00000A2803000006732300000A0C09086F2400000A11056F2500000A3A39FFFFFFDE161105751A0000012C0C1105751A0000016F2600000ADC092A000000010C000002000600DBE10016000000011B3004007200000004000011026F2700000A6F2800000A0C2B45086F1C00000A741B0000010A16026F1A00000A6F2900000A17DA0D0B2B180307066F2A00000A079A282B00000A6F2C00000A0717D60B070931E4282D00000A036F2E00000A086F2500000A2DB3DE1408751A0000012C0B08751A0000016F2600000ADC2A0000010C0000020000005D5D0014000000011B3005000E0200000500001102030E060E070428020000060C08732F00000A0B733000000A0A733100000A130406076F3200000A06166F3300000A06176F3400000A06056F3500000A076F3600000A0E0439B301000006733700000A0D0E055014FE010E08724900007016281200000A16FE015F2C56724B000070733800000A1304091104176F3900000A260E05110428040000066F3A00000A733B00000A510E05506F3C00000A1633060E051451DE1B282D00000A0E05506F3D00000ADE0C280C00000A280D00000ADE000911046F3E00000A2611046F2700000A6F3F00000A1307076F4000000A0E08724900007016281200000A1640060100000E05502D210E05110428040000066F3A00000A733B00000A51282D00000A0E05506F3D00000A11040E05502805000006DDE6000000280C00000A11046F4100000A130511056F1A00000A6F1B00000A130A2B39110A6F1C00000A7414000001130811086F1D00000A6F1100000A722F00007016281200000A1633111108D026000001284200000A6F4300000A110A6F2500000A2DBEDE16110A751A0000012C0C110A751A0000016F2600000ADC11046F2700000A6F2800000A130B2B17110B6F1C00000A741B0000011309110511096F4400000A110B6F2500000A2DE0DE16110B751A0000012C0C110B751A0000016F2600000ADC11050E05502805000006280D00000ADE150E091104512B0E066F4500000A1307076F4000000A11072A000001300000000076003EB4000C0A00000102003301548701160000000102009D0132CF011600000001000016010F2501D10A0000011B300A007204000006000011725B000070732F00000A130A733000000A0B733000000A0A733100000A1306733100000A130716130F733100000A1308733000000A0C110A6F3600000A0E0539E00000000713141114110A6F3200000A1114166F3300000A11141A6F3400000A1114728B0000706F3500000A11146F4600000A72B90000701E6F4700000A2611146F4600000A72B90000706F4800000A028C180000016F4900000A11146F4600000A72C90000701F0C20FF0000006F4A00000A2614131407733700000A0D0613151115110A6F3200000A1115166F3300000A11151A6F3400000A111572E10000706F3500000A11156F4600000A720B0100701E6F4700000A2611156F4600000A721B0100701E6F4700000A2611156F4600000A723D0100701F16156F4A00000A26141315036F2700000A6F2800000A1316381F02000011166F1C00000A741B00000113100E052C5E16130D076F4600000A72C90000706F4800000A111072590100706F4B00000A6F4C00000A6F4900000A0911076F3E00000A2611076F2700000A166F4D00000A726F0100706F4B00000A281700000A130F11076F4E00000A733100000A1307111072590100706F4B00000A6F4C00000A1110727D0100706F4B00000A284F00000A04050E04120C0E060E070E0812052806000006130D0E090E094A110DD6540E08724900007016281200000A163BA100000011086F2700000A6F3F00000A16334A0813171117110A6F3200000A1117166F3300000A1117176F3400000A111772AD0100700E0872CD010070285000000A6F3500000A14131708733700000A130411041108176F3900000A2611056F2700000A6F2800000A13182B1711186F1C00000A741B0000011311110811116F4400000A11186F2500000A2DE0DE161118751A0000012C0C1118751A0000016F2600000ADCDDB600000025280C00000A1309280D00000ADDA4000000110F163B9400000006131911196F4600000A720B0100706F4800000A110F8C180000016F4900000A11196F4600000A721B0100706F4800000A110D8C180000016F4900000A11092D1D11196F4600000A723D0100706F4800000A7E5100000A6F4900000A2B2611196F4600000A723D0100706F4800000A11096F5200000A6F4900000A110B17D6130B14130911196F4500000A2614131916130F2B0711092C0311097ADC11166F2500000A3AD5FDFFFFDE161116751A0000012C0C1116751A0000016F2600000ADC0E04282D00000A6F5300000A5F2C0A282D00000A6F5400000ADDD8000000110914FE010E08724900007016281200000A16FE0116FE015F2C6011086F2700000A6F2800000A131A2B15111A6F1C00000A741B000001131311136F5500000A111A6F2500000A2DE2DE16111A751A0000012C0C111A751A0000016F2600000ADC1104735600000A1312110411086F5700000A2611046F5800000A110A2C18110A6F5900000A162E07110A6F4000000A110A6F5800000A072C06076F5800000A062C06066F5800000A092C06096F5800000A11082C03141308082D02140C11042D03141304110914FE0116FE010216FE015F2C0311097ADC110B2A00004190000002000000520200003200000084020000160000000000000100000000440100005B0100009F020000120000000A00000102000000440100006D010000B1020000A40000000000000102000000240100003F02000063030000160000000000000102000000B203000030000000E2030000160000000000000102000000360000006103000097030000D800000000000001133002000C000000070000110272D1010070280A0000062A133002000C000000080000110272D1010070280B0000062A1B300400C800000009000011168D320000010A1E8D3200000113081108161F129C1108171F349C1108181F569C1108191F789C11081A20900000009C11081B20AB0000009C11081C20CD0000009C11081D20EF0000009C11080C285A00000A031E285B00000A6F5C00000A0A735D00000A1304285A00000A026F5C00000A1305735E00000A13061106110406086F5F00000A17736000000A0D0911051611058EB76F6100000A096F6200000A11066F6300000A286400000A0BDE1725280C00000A130711076F5200000A0B280D00000ADE00072A010C000000004E0061AF00170A0000011B300400DA0000000A000011168D320000010A1E8D3200000113091109161F129C1109171F349C1109181F569C1109191F789C11091A20900000009C11091B20AB0000009C11091C20CD0000009C11091D20EF0000009C11090D026F6500000A17D68D320000010C285A00000A031E285B00000A6F5C00000A0A735D00000A130502286600000A0C735E00000A13071107110506096F6700000A17736000000A130411040816088EB76F6100000A11046F6200000A285A00000A1306110611076F6300000A6F6800000A0BDE1725280C00000A130811086F5200000A0B280D00000ADE00072A0000010C000000005C0065C100170A0000011B300A00E80400000B000011725B000070732F00000A1307733000000A0B733100000A0D733100000A13041613091613080E04390902000011076F3600000A07130D110D11076F3200000A110D166F3300000A110D1A6F3400000A110D72E30100706F3500000A110D6F4600000A7211020070026F6900000A2607733700000A0C08096F3E00000A26096F2700000A6F2800000A130E2B26110E6F1C00000A741B000001130B110B727D0100706F4B00000A286A00000A2D05171306DE21110E6F2500000A2DD1DE16110E751A0000012C0C110E751A0000016F2600000ADC110D72290200706F3500000A110D6F4600000A724B020070036F6900000A26110D6F4600000A725F020070046F6900000A26110D6F4600000A7271020070058C390000016F6900000A26110D6F4600000A72910200700E088C180000016F6900000A2614130D07733700000A0C0811046F3E00000A2611046F2700000A166F4D00000A72A90200706F4B00000A281700000A130911060E06724900007016281200000A16FE015F39AA000000141304733100000A130407130F110F72B70200706F3500000A110F6F4600000A6F6B00000A110F6F4600000A72F10200701F0C20FF0000006F4A00000A26110F6F4600000A72F10200706F4800000A0E056F4900000A14130F07733700000A0C0811046F3E00000A2611046F2700000A166F4D00000A72050300706F4B00000A286C00000A100511046F2700000A166F4D00000A72170300706F4B00000A286C00000A2809000006100611076F4000000A3899000000161309096F1A00000A7259010070D02B000001284200000A6F6D00000A26096F1A00000A727D010070D039000001284200000A6F6D00000A2602722F0300701516286E00000A0A0613111613102B42111111109A130C096F2700000A188D010000011312111216110CA21112170E05724900007016281200000A16FE018C39000001A211126F6F00000A26111017D61310111011118EB732B61109090304050E040E050E060E07120A28070000061308DDFD01000025280C00000A1305110817D6130811057A110514FE010516FE010E07724900007016281200000A16FE0116FE01605F39CB00000011076F5900000A172E0711076F3600000A071313111311076F3200000A1113166F3300000A1113176F3400000A11136F4600000A6F6B00000A111372330300706F3500000A14131307733700000A0C733100000A13040811046F3E00000A2611046F2700000A166F4D00000A723E0500706F4B00000A281700000A16334D110A163222282D00000A724C050070120A287000000A7250050070285000000A6F7100000A2B26282D00000A727405007016110ADA13141214287000000A7294050070285000000A6F7100000A1109163BB300000011076F5900000A162E0711076F4000000A11076F3600000A071315733000000A0B111511076F3200000A1115166F3300000A11151A6F3400000A111572AA0500706F3500000A11156F4600000A6F6B00000A11156F4600000A72B900007011098C180000016F6900000A2611156F4600000A72C805007011088C180000016F6900000A2611052C1911156F4600000A723D01007011056F5200000A6F6900000A2611156F4500000A2614131511076F4000000A11072C1811076F5900000A162E0711076F4000000A11076F5800000A072C06076F5800000A082C06086F5800000A092C06096F4E00000A11042C0711046F4E00000ADC2A41480000020000007D00000040000000BD00000016000000000000010000000025000000C5020000EA020000110000000A0000010200000025000000D6020000FB020000EC0100000000000142534A4201000100000000000C00000076322E302E35303732370000000005006C000000E8070000237E000054080000B00B000023537472696E67730000000004140000E805000023555300EC190000100000002347554944000000FC190000EC03000023426C6F620000000000000002000001571D02080902000000FA013300160000010000004600000003000000040000000C0000002C0000007D0000000A0000000C0000000B000000010000000100000004000000010000000000A70B0100000000000600490042000E00C400B8000600CE00420006000F01F4000E00310116010E003D01B8000E005A0116010600C60242000E001103FB0206002C0342000E00D103BE030A00270400040E005504FB021200780462040E008604B8001200980462040A00BD04000406000105EF040A00210500040E004505B8000600630550050E006F05B8000E009005B8000600EF0542000A00F50513000600190642000E002D06B8000E003506B8000600880668060E00AF0616010E00BA0616010E00DA06FB020E00E506FB020E00F306FB020E002407B8000E005507BE030E006307B8000600B20742000600B80742000E000308FB020E001508FB0212004E08620406006D08420006007B0842001200C80862040E00D208B80006000909EC0806001609EC08060039092F09060046094200060057094B090A006909130006007F09EC080600A0092F090600A709EC080600CE0942000600320A42000A00400A13000600590A68060600790A68060600970AEF040600D30AB40A0600E10AB40A0600F50A420006000B0BEF040600260BEF040600410BEF0406005A0BEF040600730BEF040600900BEF0400000000010000000000010001000100000029000000050001000100030100002D000000210002000D005180560017000606CB02BE005680D302C1005680E502C10050200000000006185000130001005820000000001100620049000100D420000000001100D300600006009421000000001100470167000700AC220000000011006801720008003C2300000000110085017A000A008C25000000001100FB018D001400A02A00000000160033029D001E00B82A00000000110053029D001F00D02A0000000011007502A2002000B42B0000000011009002A2002200AC2C000000001600A102A8002400000001007800000002008300000003009600000004009F0010100500AB0000000100EC00000001005601000001005601000002007E0100000100960100000200A10100000300B60100000400BF0100000500C70100000600D801000007009600000008009F0000000900DF0100000A00EB01000001000D0200000200140200000300B60100000400BF0100000500C701000006002102000007009600000008009F0000000900DF0100000A002902000001004702000001006302000001007D02000002008502000001007D0200000200980200000100B00200000200B60100000300BF0110100400C701101005002102101006009600101007009F0010100800DF0110100900BB0209005000130049005000130049003603C50049004503C50049005803CA0049006F03CF0049008603C50049009103C50049009E03C5004900B203CA005900EB03D30061003304D70061004304DD0069005000130069008D04EB008100A704F0001900B404D3008900C704F6006900D504FD007100E004030191000C05D30071001505090199002D050E016900370513010C0050001300310084052A01B900AB052F01A900B9053401A100C5053801A100D205D300A100E1053D01C90001064101990005064801290050004D012900500055010C000C065C01A9001006CF00D10025061300310047067901E100AB052F01B90050063D01D9005A067E01E900970683013900A6068801F100C2068E01F900CB06930109015000C50001015000130031005000130001010207A20101011107A90101013007AE0101014007C50009015007130011015000B50131005000C50021016E07BC010C007907C60139005000CC01390081073D01F900900793012101A107D301E10050063D010901A60713003100AC07D9011900CA07DE01A100DC07E6013100E907EC010101F3073D0101012C080D0249010C06130249013B081B0269004408210249010C062602D9003B082F020900B404D300E1003B083402510125061300990066083A02590174083F0261018208460251008808D300F9009408CF00F900A9081300D900B8081300410150004B022101C108D3016901250613000901E2085202990160099C02A1017109A20299017609A80281015000130089015000130081019009AE0279015000B8027901B809C5027901BE09130089017907CD02C101D609D2025901E5093D01C101F009EF028101010AAE029901110AF50249011B0A15039900280A1C0349013A0A13009900B4042103B1000C062603A1014E0A2E03E1000C063903C100B404D300F900540AC500D9015000A901E10150001300E9015000C500F1015000C500F9015000CA0001025000CA0009025000C50011025000C50019025000C50021025000C50029025000C50031025000C5000E0004001A0005000C00B70005001000B5000E001500530002009D00B5000200A100B7000E00A50000000E00A90000000E00AD0000000800B100B9002E0093036F032E009B0378032E00A30397032E00AB03A2032E00B303CC032E00BB03D2032E00C303CC032E00CB03CC032E00D303D8032E00DB03E1032E00E303CC032E00EB03D803E100180162019901F201580298029802D802FB02400323010480000002000000A6114E480000000000002900000002000000000000000000000001000A00000000000800000000000000000000000A001300000000000200000000000000000000000100B8000000000002000000000000000000000001004200000000000300020000000000003C4D6F64756C653E006D73636F726C6962004D6963726F736F66742E56697375616C42617369630053594C0041757468657469636174696F6E4D6574686F64730053797374656D004F626A656374002E63746F72006D5F436F6E537472696E67004275696C64436F6E6E656374696F6E537472696E67005365727665726E616D650041757468656E7469636174696F6E547970650053716C4C6F67696E0053716C50617373776F72640044617461626173654E616D650053797374656D2E446174610053716C446254797065005479706500436F6E7665727454797065546F53514C446174615479706500746865547970650053797374656D2E436F6C6C656374696F6E732E47656E65726963004C6973746031004D6963726F736F66742E53716C5365727665722E5365727665720053716C4D6574614461746100446174615461626C65004765745461626C65536368656D610074626C0053716C446174615265636F72640053656E64446174615461626C654F76657250697065007265636F726400476574536572766572526573756C7473005365727665724E616D650041757468656E7469636174696F6E4D6574686F6400446174616261736500436F6D6D616E64004973526573756C744578706563746564005265636F7264004F75747075745461626C65006474536572766572526573756C74730052756E5468726F756768536572766572730052554E5F494400536572766572735461626C65004C6F67546F444200546F74616C526F7773007564665F456E637279707450617373776F72640073716C50617373776F7264004465637279707450617373776F726400456E6372797074656450617373776F726400456E6372797074007374725465787400737472456E63724B657900446563727970740073446563724B6579007573705F52756E436F6D6D616E64005365727665724C697374004964656E74696669657200456E756D0076616C75655F5F0053514C41757468656E7469636174696F6E0057696E646F777341757468656E7469636174696F6E0053797374656D2E446174612E53716C436C69656E740053716C436F6E6E656374696F6E537472696E674275696C64657200457863657074696F6E007365745F44617461536F75726365007365745F496E697469616C436174616C6F67007365745F496E74656772617465645365637572697479006765745F496E74656772617465645365637572697479007365745F557365724944007365745F50617373776F7264007365745F4170706C69636174696F6E4E616D65007365745F506F6F6C696E670053797374656D2E446174612E436F6D6D6F6E004462436F6E6E656374696F6E537472696E674275696C646572006765745F436F6E6E656374696F6E537472696E67004D6963726F736F66742E56697375616C42617369632E436F6D70696C657253657276696365730050726F6A656374446174610053657450726F6A6563744572726F7200436C65617250726F6A6563744572726F720053716C506172616D657465720053797374656D2E436F6D706F6E656E744D6F64656C0054797065436F6E76657274657200446254797065006765745F446254797065005479706544657363726970746F7200476574436F6E76657274657200546F537472696E67004F70657261746F727300436F6D70617265537472696E67007365745F4462547970650043616E436F6E7665727446726F6D0053797374656D2E5265666C656374696F6E004D656D626572496E666F006765745F4E616D6500436F6E7665727446726F6D00436F6E76657273696F6E7300546F496E7465676572006765745F53716C4462547970650044617461436F6C756D6E0053797374656D2E436F6C6C656374696F6E730049456E756D657261746F720044617461436F6C756D6E436F6C6C656374696F6E006765745F436F6C756D6E7300496E7465726E616C44617461436F6C6C656374696F6E4261736500476574456E756D657261746F72006765745F43757272656E74006765745F4461746154797065006765745F436F6C756D6E4E616D65006765745F4D61784C656E67746800496E74333200496E746572616374696F6E0049496600546F4C6F6E6700416464004D6F76654E6578740049446973706F7361626C6500446973706F73650044617461526F770044617461526F77436F6C6C656374696F6E006765745F526F7773006765745F436F756E74006765745F4974656D41727261790053797374656D2E52756E74696D652E436F6D70696C657253657276696365730052756E74696D6548656C70657273004765744F626A65637456616C75650053657456616C75650053716C436F6E746578740053716C50697065006765745F506970650053656E64526573756C7473526F770053716C436F6D6D616E640053716C436F6E6E656374696F6E0053716C4461746141646170746572007365745F436F6E6E656374696F6E007365745F436F6D6D616E6454696D656F757400436F6D6D616E6454797065007365745F436F6D6D616E6454797065007365745F436F6D6D616E6454657874004F70656E004462446174614164617074657200536368656D61547970650046696C6C536368656D6100546F4172726179006765745F4669656C64436F756E740053656E64526573756C747353746172740046696C6C00436C6F736500436C6F6E6500496E7436340052756E74696D655479706548616E646C65004765745479706546726F6D48616E646C65007365745F446174615479706500496D706F7274526F7700457865637574654E6F6E51756572790053716C436F6D6D616E644275696C6465720053716C506172616D65746572436F6C6C656374696F6E006765745F506172616D6574657273006765745F4974656D007365745F56616C7565004D61727368616C427956616C7565436F6D706F6E656E7400546F4279746500537472696E6700436F6E6361740044424E756C6C0056616C7565006765745F4D657373616765006765745F497353656E64696E67526573756C74730053656E64526573756C7473456E640053657441646465640055706461746500436F6D706F6E656E7400436F6E6E656374696F6E5374617465006765745F53746174650053797374656D2E53656375726974792E43727970746F6772617068790043727970746F53747265616D0044455343727970746F5365727669636550726F76696465720053797374656D2E494F004D656D6F727953747265616D00427974650053797374656D2E5465787400456E636F64696E67006765745F5554463800537472696E6773004C656674004765744279746573004943727970746F5472616E73666F726D00437265617465456E63727970746F720053747265616D0043727970746F53747265616D4D6F646500577269746500466C75736846696E616C426C6F636B00436F6E7665727400546F426173653634537472696E67006765745F4C656E6774680046726F6D426173653634537472696E6700437265617465446563727970746F7200476574537472696E67004164645769746856616C756500546F426F6F6C65616E00426F6F6C65616E00436C65617200436F6D706172654D6574686F640053706C69740053656E6400436F6D70696C6174696F6E52656C61786174696F6E734174747269627574650052756E74696D65436F6D7061746962696C69747941747472696275746500417373656D626C7946696C6556657273696F6E4174747269627574650053797374656D2E52756E74696D652E496E7465726F705365727669636573004775696441747472696275746500436F6D56697369626C6541747472696275746500434C53436F6D706C69616E7441747472696275746500417373656D626C7954726164656D61726B41747472696275746500417373656D626C79436F7079726967687441747472696275746500417373656D626C7950726F6475637441747472696275746500417373656D626C79436F6D70616E7941747472696275746500417373656D626C794465736372697074696F6E41747472696275746500417373656D626C795469746C654174747269627574650053594C2E646C6C00000011530059004C0020003200300030003500001B530079007300740065006D002E0042007900740065005B005D000019530079007300740065006D002E0049006E007400330032000001000F52006500730075006C0074007300002F63006F006E007400650078007400200063006F006E006E0065006300740069006F006E003D007400720075006500002D530059004C002E007500730070005F0053007400610072007400530065007200760065007200520075006E00000F4000520055004E005F0049004400001740005300650072007600650072004E0061006D0065000029530059004C002E007500730070005F0045006E006400530065007200760065007200520075006E00000F40005300520052005F0049004400002140005200650063006F0072006400730041006600660065006300740065006400001B40004500720072006F0072004D0065007300730061006700650000155300650072007600650072004E0061006D006500000D5300520052005F0049004400002F49007300570069006E0064006F0077007300410075007400680065006E007400690063006100740069006F006E00001F530045004C0045004300540020002A002000460052004F004D0020005B0000035D00001126002500230040003F002C003A002A00002D530059004C002E007500730070005F0047006500740053006500720076006500720073004C00690073007400001740005300650072007600650072004C006900730074000021530059004C002E007500730070005F0053007400610072007400520075006E0000134000440061007400610062006100730065000011400043006F006D006D0061006E006400001F4000450078007000650063007400730052006500730075006C0074007300001740004900640065006E00740069006600690065007200000D520055004E005F00490044000039530059004C002E007500730070005F00520065007400720069006500760065004C006F00670069006E00440065007400610069006C00730000134000530071006C004C006F00670069006E000011530071006C004C006F00670069006E000017530071006C00500061007300730077006F007200640000032C0000820963007200650061007400650020007400610062006C00650020002300530065007400740069006E00670073002800530065007400740069006E00670020006E007600610072006300680061007200280035003000300029002C002000560061006C002000730071006C005F00760061007200690061006E0074002900200069006E007300650072007400200069006E0074006F0020002300530065007400740069006E0067007300200065007800650063002000730070005F006500780065006300750074006500730071006C0020004E0027004400420043004300200055005300450052004F005000540049004F004E0053002000570049005400480020004E004F005F0049004E0046004F004D0053004700530027002000730065006C006500630074002000690073006E0075006C006C0028002800730065006C00650063007400200074006F00700020003100200031002000660072006F006D0020002300530065007400740069006E00670073002000770068006500720065002000530065007400740069006E00670020003D00200027006E006F0063006F0075006E0074002700200061006E0064002000560061006C0020003D0020002700530045005400270029002C00200030002900200052006500730075006C0074002000640072006F00700020007400610062006C00650020002300530065007400740069006E0067007300010D52006500730075006C007400000328000023200072006F0077002800730029002000610066006600650063007400650064002900001F43006F006D006D0061006E0064002000720061006E0020006F006E00200000152000730065007200760065007200280073002900001D530059004C002E007500730070005F0045006E006400520075006E00001F40004E0075006D006200650072004F0066004500720072006F007200730000C990BC3110542C4B98AA8776B22246660008B77A5C561934E08908B03F5F7F11D50A3A0320000102060E2E63006F006E007400650078007400200063006F006E006E0065006300740069006F006E003D0074007200750065000900050E0E110C0E0E0E0C6D00610073007400650072000600011109120D0A00011512110112151219070002011219121D12000A080E110C0E0E0210121D0E0E0E1012190F000A080812190E0E02020E0E0E10080400010E0E0500020E0E0E0C0009010E0E0E02020E0E0E080101010004000000000206050306110C042001010E0420010102032000020320000E050001011229030000010907040E122512291225042000113D05000112391C060003080E0E0205200101113D05200102120D0420011C1C040001081C04200011090A0704110912351239122906151211011215042000125904200012550320001C042000120D032000080600031C021C1C0400010A1C072003010E11090A062002010E1109052001011300160706110915121101121512151512110112151251125504200012710420001D1C0400011C1C05200201081C040000127D05200101121D080704126D081255080620010112808504200101080620010111808D06200101128081092002121912191180950520001D1300062001011D12150520010812190420001219070001120D11809D05200101120D05200101126D1A070C1280811280850E1280891219121908081251126D125512550520001280A507200212350E110905200112350E042001011C08200312350E1109080420011C0E052001126D08040001051C0600030E0E0E0E04061280B1062001011280890520001180B93F071B1280811280811280811280891280891219121912191219122912808508121D080808126D126D1280A1126D1280811280811255128081125512808112550307010E0500001280CD0500020E0E080520011D050E0920021280D51D051D050C2003011280D91280D51180DD072003011D0508080420001D050500010E1D051607091D050E1D051280BD1280C11D051280C512291D050500011D050E0520010E1D0519070A1D050E1D051D051280BD1280C11280CD1280C512291D0506200212350E1C040001021C0400010E1C07200212510E120D0A00041D0E0E0E081180E9062001126D1D1C2E07161D0E12808112808912191219122902128085080808126D0E1280811255128081081D0E1D1C128081081280810801000800000000001E01000100540216577261704E6F6E457863657074696F6E5468726F7773010A010005322E302E3000002901002438333837323436312D633264652D346339332D383932342D36383230383131356539366400000501000000000501000100000801000353594C00000801000338383800000000FC4F000000000000000000001E500000002000000000000000000000000000000000000000000000105000000000000000000000000000000000000000005F436F72446C6C4D61696E006D73636F7265652E646C6C0000000000FF2500204000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030003000000280000800E000000480000801000000060000080000000000000000000000000000002000200000078000080030000009000008000000000000000000000000000000100007F0000A80000800000000000000000000000000000010001000000C00000800000000000000000000000000000010000000000D80000000000000000000000000000000000010000000000E80000000000000000000000000000000000010000000000F8000000000000000000000000000000000001000000000008010000A8630000E8020000000000000000000090660000280100000000000000000000B867000022000000000000000000000018610000900200000000000000000000900234000000560053005F00560045005200530049004F004E005F0049004E0046004F0000000000BD04EFFE00000100000002000000000000000200000000003F000000000000000400000002000000000000000000000000000000440000000100560061007200460069006C00650049006E0066006F00000000002400040000005400720061006E0073006C006100740069006F006E00000000000000B004F0010000010053007400720069006E006700460069006C00650049006E0066006F000000CC010000010030003000300030003000340062003000000028000400010043006F006D00700061006E0079004E0061006D006500000000003800380038000000300004000100460069006C0065004400650073006300720069007000740069006F006E0000000000530059004C0000002C0006000100460069006C006500560065007200730069006F006E000000000032002E0030002E003000000030000800010049006E007400650072006E0061006C004E0061006D0065000000530059004C002E0064006C006C0000002800020001004C006500670061006C0043006F0070007900720069006700680074000000200000003800080001004F0072006900670069006E0061006C00460069006C0065006E0061006D0065000000530059004C002E0064006C006C000000280004000100500072006F0064007500630074004E0061006D00650000000000530059004C000000300006000100500072006F006400750063007400560065007200730069006F006E00000032002E0030002E003000000048000F00010041007300730065006D0062006C0079002000560065007200730069006F006E00000032002E0030002E0034003500310038002E003100380035003100300000000000280000002000000040000000010004000000000080020000000000000000000000000000000000000000000000008000008000000080800080000000800080008080000080808000C0C0C0000000FF0000FF000000FFFF00FF000000FF00FF00FFFF0000FFFFFF0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007777777777777777777777777777700444444444444444444444444444447004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF47004FFFFFFFFFFFFFFFFFFFFFFFFFFF4700488888888888888888888888888847004444444444444444444444444444470044C4C4C4C4C4C4C4C4C4ECECE49747004CCCCCCCCCCCCCCCCCCCCCCCCCCC40000444444444444444444444444444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFC00000018000000180000001800000018000000180000001800000018000000180000001800000018000000180000001800000018000000180000001800000018000000180000001800000018000000180000001800000018000000180000003C0000007FFFFFFFFFFFFFFFFFFFFFFFF2800000010000000200000000100040000000000C0000000000000000000000000000000000000000000000000008000008000000080800080000000800080008080000080808000C0C0C0000000FF0000FF000000FFFF00FF000000FF00FF00FFFF0000FFFFFF000000000000000000077777777777777744444444444444474FFFFFFFFFFFF8474FFFFFFFFFFFF8474FFFFFFFFFFFF8474FFFFFFFFFFFF8474FFFFFFFFFFFF8474FFFFFFFFFFFF8474FFFFFFFFFFFF8474FFFFFFFFFFFF84748888888888888474CCCCCCCCCCCCC47C4444444444444C000000000000000000000000000000000FFFF000080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000FFFF0000FFFF00000000010002002020100001000400E8020000020010101000010004002801000003000000000000000000000000000000000000000000000000000000000000000000000000000000005000000C000000303000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
WITH PERMISSION_SET = UNSAFE
GO
CREATE PROCEDURE SYL.usp_RunCommand
(
	@ServerList nvarchar(max),
	@Database nvarchar(128),
	@Command nvarchar(max),
	@IsResultExpected bit,
	@LogToDB bit,
	@SqlLogin nvarchar(128),
	@SqlPassword nvarchar(128),
	@OutputTable nvarchar(257),
	@Identifier int
)
AS EXTERNAL NAME SYL.SYL.usp_RunCommand
GO
CREATE FUNCTION SYL.udf_EncryptPassword
(
	@SqlPassword nvarchar(255)
) RETURNS nvarchar(max)
AS EXTERNAL NAME SYL.SYL.udf_EncryptPassword
GO