THEME=
{
	CODE =
	{
		BG     =15,
		FG     =12,
		STRING =4,
		NUMBER =11,
		KEYWORD=3,
		API    =5,
		COMMENT=14,
		SIGN   =13,
		SELECT =14,
		CURSOR =2,
		SHADOW =true,
		ALT_FONT=false,
		MATCH_DELIMITERS=true,
	},

	GAMEPAD=
	{
		TOUCH=
		{
			ALPHA=180,
		},
	},
}

CHECK_NEW_VERSION=true
NO_SOUND=false
GIF_LENGTH=20 -- in seconds
SOFTWARE_RENDERING=false
CRT_MONITOR=false
GIF_SCALE=3
UI_SCALE=4

---------------------------
function TIC()
	cls()
	local label="This is system configuration cartridge"
	local size=print(label,0,-6)
	print(label,(240-size)//2,(136-6)//2)
end

CRT_SHADER=
{
	VERTEX=[[
		#version 110
		attribute vec3 gpu_Vertex;
		attribute vec2 gpu_TexCoord;
		attribute vec4 gpu_Color;
		uniform mat4 gpu_ModelViewProjectionMatrix;
		varying vec4 color;
		varying vec2 texCoord;
		void main(void)
		{
			color = gpu_Color;
			texCoord = vec2(gpu_TexCoord);
			gl_Position = gpu_ModelViewProjectionMatrix * vec4(gpu_Vertex, 1.0);
		}
	]],
	PIXEL=[[
		#version 110
		//precision highp float;
		varying vec2 texCoord;
		uniform sampler2D source;
		uniform float trg_x;
		uniform float trg_y;
		uniform float trg_w;
		uniform float trg_h;
		uniform float scr_w;
		uniform float scr_h;

		// Emulated input resolution.
		vec2 res=vec2(256.0,144.0);

		// Hardness of scanline.
		//  -8.0 = soft
		// -16.0 = medium
		float hardScan=-8.0;

		// Hardness of pixels in scanline.
		// -2.0 = soft
		// -4.0 = hard
		float hardPix=-3.0;

		// Display warp.
		// 0.0 = none
		// 1.0/8.0 = extreme
		vec2 warp=vec2(1.0/64.0,1.0/48.0); 

		// Amount of shadow mask.
		float maskDark=0.5;
		float maskLight=1.5;

		//------------------------------------------------------------------------

		// sRGB to Linear.
		// Assuing using sRGB typed textures this should not be needed.
		float ToLinear1(float c){return(c<=0.04045)?c/12.92:pow((c+0.055)/1.055,2.4);}
		vec3 ToLinear(vec3 c){return vec3(ToLinear1(c.r),ToLinear1(c.g),ToLinear1(c.b));}

		// Linear to sRGB.
		// Assuing using sRGB typed textures this should not be needed.
		float ToSrgb1(float c){return(c<0.0031308?c*12.92:1.055*pow(c,0.41666)-0.055);}
		vec3 ToSrgb(vec3 c){return vec3(ToSrgb1(c.r),ToSrgb1(c.g),ToSrgb1(c.b));}

		// Nearest emulated sample given floating point position and texel offset.
		// Also zero's off screen.
		vec3 Fetch(vec2 pos,vec2 off){
			pos=(floor(pos*res+off)+vec2(0.5,0.5))/res;
			return ToLinear(1.2 * texture2D(source,pos.xy,-16.0).rgb);}

		// Distance in emulated pixels to nearest texel.
		vec2 Dist(vec2 pos){pos=pos*res;return -((pos-floor(pos))-vec2(0.5));}
				
		// 1D Gaussian.
		float Gaus(float pos,float scale){return exp2(scale*pos*pos);}

		// 3-tap Gaussian filter along horz line.
		vec3 Horz3(vec2 pos,float off){
			vec3 b=Fetch(pos,vec2(-1.0,off));
			vec3 c=Fetch(pos,vec2( 0.0,off));
			vec3 d=Fetch(pos,vec2( 1.0,off));
			float dst=Dist(pos).x;
			// Convert distance to weight.
			float scale=hardPix;
			float wb=Gaus(dst-1.0,scale);
			float wc=Gaus(dst+0.0,scale);
			float wd=Gaus(dst+1.0,scale);
			// Return filtered sample.
			return (b*wb+c*wc+d*wd)/(wb+wc+wd);}

		// 5-tap Gaussian filter along horz line.
		vec3 Horz5(vec2 pos,float off){
			vec3 a=Fetch(pos,vec2(-2.0,off));
			vec3 b=Fetch(pos,vec2(-1.0,off));
			vec3 c=Fetch(pos,vec2( 0.0,off));
			vec3 d=Fetch(pos,vec2( 1.0,off));
			vec3 e=Fetch(pos,vec2( 2.0,off));
			float dst=Dist(pos).x;
			// Convert distance to weight.
			float scale=hardPix;
			float wa=Gaus(dst-2.0,scale);
			float wb=Gaus(dst-1.0,scale);
			float wc=Gaus(dst+0.0,scale);
			float wd=Gaus(dst+1.0,scale);
			float we=Gaus(dst+2.0,scale);
			// Return filtered sample.
			return (a*wa+b*wb+c*wc+d*wd+e*we)/(wa+wb+wc+wd+we);}

		// Return scanline weight.
		float Scan(vec2 pos,float off){
			float dst=Dist(pos).y;
			return Gaus(dst+off,hardScan);}

		// Allow nearest three lines to effect pixel.
		vec3 Tri(vec2 pos){
			vec3 a=Horz3(pos,-1.0);
			vec3 b=Horz5(pos, 0.0);
			vec3 c=Horz3(pos, 1.0);
			float wa=Scan(pos,-1.0);
			float wb=Scan(pos, 0.0);
			float wc=Scan(pos, 1.0);
			return a*wa+b*wb+c*wc;}

		// Distortion of scanlines, and end of screen alpha.
		vec2 Warp(vec2 pos){
			pos=pos*2.0-1.0;    
			pos*=vec2(1.0+(pos.y*pos.y)*warp.x,1.0+(pos.x*pos.x)*warp.y);
			return pos*0.5+0.5;}

		// Shadow mask.
		vec3 Mask(vec2 pos){
			pos.x+=pos.y*3.0;
			vec3 mask=vec3(maskDark,maskDark,maskDark);
			pos.x=fract(pos.x/6.0);
			if(pos.x<0.333)mask.r=maskLight;
			else if(pos.x<0.666)mask.g=maskLight;
			else mask.b=maskLight;
			return mask;}    

		void main() {
			hardScan=-12.0;
			//maskDark=maskLight;
			vec2 start=gl_FragCoord.xy-vec2(trg_x, trg_y);
			start.y=scr_h-start.y;

			vec2 pos=Warp(start/vec2(trg_w, trg_h));

			gl_FragColor.rgb=Tri(pos)*Mask(gl_FragCoord.xy);
			gl_FragColor = vec4(ToSrgb(gl_FragColor.rgb), 1.0);
		}
	]]
}

-- <TILES>
-- 000:eccccccccc888888caaaaaaaca888888cacccccccacc0ccccacc0ccccacc0ccc
-- 001:ccccceee8888cceeaaaa0cee888a0ceeccca0ccc0cca0c0c0cca0c0c0cca0c0c
-- 002:eccccccccc111111c2222222c2111111c2ccccccc2cc0cccc2cc0cccc2cc0ccc
-- 003:ccccceee1111ccee22220cee11120ceeccc20cee0cc20cee0cc20cce0cc200cc
-- 004:eccccccccc222222c3333333c3222222c3ccccccc3c0ccccc3cc0cccc3cc0ccc
-- 005:ccccceee2222ccee33330cee22230ceeccc30ceec0c30cee0cc30cce0cc300cc
-- 006:eccccccccc777777c6666666c6777777c6ccccccc6ccccccc6c000c0c6cccccc
-- 007:ccccceee7777ccee66660cee77760ceeccc60cccccc60c0c00c60c0cccc60c0c
-- 008:0dddddd0dddddddddddeedddddeeeedddeeeeeedddddddddedddddde0eeeeee0
-- 009:0dddddd0dddddddddeeeeeedddeeeedddddeedddddddddddedddddde0eeeeee0
-- 010:0dddddd0ddddeddddddeedddddeeeddddddeedddddddedddedddddde0eeeeee0
-- 011:0dddddd0dddedddddddeeddddddeeedddddeeddddddeddddedddddde0eeeeee0
-- 012:0666666066677666667667666676676666777766667667667666666707777770
-- 013:0222222022111222221221222211122222122122221112221222222101111110
-- 014:0aaaaaa0aa9aa9aaaa9aa9aaaaa99aaaaa9aa9aaaa9aa9aa9aaaaaa909999990
-- 015:0333333033233233332332333332223333333233333223332333333202222220
-- 016:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 017:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- 018:c2ccccccc2222222c2222cccc222c222c2222222c1111111cc000cccecccccec
-- 019:ccc20c0c22220c0c22220c0cc2220ccc22220cee1111ccee000cceeecccceeee
-- 020:c3ccccccc3333333c33c3c3cc333c3c3c3333333c2222222cc000cccecccccec
-- 021:ccc30c0c33330c0c3c330c0cc3330ccc33330cee2222ccee000cceeecccceeee
-- 022:c6ccccccc6666666c666ccccc6666cccc6666666c7777777cc000cccecccccec
-- 023:ccc600cc66660ccec6660cee66660cee66660cee7777ccee000cceeecccceeee
-- 024:000000000dddddd0dddddddddddeedddddeeeedddeeeeeeddddddddd0dddddd0
-- 025:000000000dddddd0dddddddddeeeeeedddeeeedddddeeddddddddddd0dddddd0
-- 026:000000000dddddd0ddddeddddddeedddddeeeddddddeedddddddeddd0dddddd0
-- 027:000000000dddddd0dddedddddddeeddddddeeedddddeeddddddedddd0dddddd0
-- 028:0000000006666660666776666676676666766766667777666676676606666660
-- 029:0000000002222220221112222212212222111222221221222211122202222220
-- 030:000000000aaaaaa0aa9aa9aaaa9aa9aaaaa99aaaaa9aa9aaaa9aa9aa0aaaaaa0
-- 031:0000000003333330332332333323323333322233333332333332233303333330
-- 032:eccccccccc111111c2222222c2111111c2ccccccc2c2c2c2c2c222c2c2cc2ccc
-- 033:ccccceee1111ccee22220cee11120ceeccc20cccc2c20c0c22c20c0c2cc20c0c
-- 036:0000000076555670000000000000000000000000000000000000000000000000
-- 039:ccc33333ccc33333ccc33333ccc33333ccc33333ccccc033ccccc033ddddd033
-- 040:33333333ccc33333ccc33333ccc33333ccc33333cccdd033ccccc033ccccc033
-- 041:3330000033300000333fffff33300000333dd0dd333333333333333333333333
-- 042:33300000333000003330000033300000333fffff333333333333333333333333
-- 048:c2ccccccc2222222c222ccccc2222cccc2222222c1111111cc000cccecccccec
-- 049:ccc200cc22220ccec2220cee22220cee22220cee1111ccee000cceeecccceeee
-- 052:000000000fffff00000000000000000000000000000000000000000000000000
-- 080:0000000000c0c00000c0c000000c00000cc0cc000cc0cc000000000000000000
-- 081:000000000cccc0000c00c0000c0ccc000ccc0c00000ccc000000000000000000
-- 082:0000000000ccc0000c000c000ccccc000cc0cc000ccccc000000000000000000
-- 083:00000000000cc00000cc00000ccccc0000cc0000000cc0000000000000000000
-- 084:0000000000cc0000000cc0000ccccc00000cc00000cc00000000000000000000
-- 085:000000000ccccc000c000c000c000c000ccccc000cccc0000000000000000000
-- 086:0000000000ccc00000c0c0000ccccc00000c0000000c00000000000000000000
-- 087:ccccccc0ccccccc0ccccccc0ccccccc0ccccccc0ccccccc0ccccccc000000000
-- 088:000000000cc0cc000c000c000c000c000c000c000cc0cc000000000000000000
-- 089:0000000000ccc0000c0c0c000ccccc000ccccc000c0c0c000000000000000000
-- 090:000000000cc0cc000cc0cc00000000000cc0cc000cc0cc000000000000000000
-- 091:00000000000cc00000cc0c000ccc0c0000cc0c00000cc0000000000000000000
-- 092:0000000000cccc0000c00c0000c00c000cc0cc000cc0cc000000000000000000
-- 093:0000000000ccc00c0ccccc0c0ccccc0c0ccccc0c00ccc00c0000000000000000
-- 094:00000000c00cc00c0c0c00c0c00cc0c00c0c00c00c0cc00c0000000000000000
-- 095:000000000ccccc000ccccc000ccccc000cc0cc000c000c000000000000000000
-- 096:000000000cccc0000c00cc000c00cc000ccccc0000cccc000000000000000000
-- 097:000000000000000000000c0000000c0000000c0000cccc000000000000000000
-- 098:00000000000c0000000cc000000ccc00000cc000000c00000000000000000000
-- 099:00000000000cc000000ccc000c0ccc0000cccc00000cc0000000000000000000
-- 100:0000000000ccc0000c000c000c000c0000ccc000000c00000000000000000000
-- 101:00000000000c0000000cc0000ccccc00000cc000000c00000000000000000000
-- 102:000000000ccccc00000000000ccccc00000000000ccccc000000000000000000
-- 103:00000000000ccc0000c000c00c00c00c00c000c0000ccc000000000000000000
-- 104:000000000ccccc000c0c0c000ccccc000c0c0c000ccccc000000000000000000
-- 105:00000000000000000ccccc0000ccc000000c0000000000000000000000000000
-- 106:0000000000000000000c000000ccc0000ccccc00000000000000000000000000
-- 107:000000000000c00000000c0000ccccc00c0ccc000c00c0000000000000000000
-- 108:000000000c0c0c00000000000c000c00000000000c0c0c000000000000000000
-- 109:000000000000c000000c0c0000c0c0000c0c00000cc000000000000000000000
-- 110:000000000c0c0c00000000000c0c0c00000000000c0c0c000000000000000000
-- 111:0000000000ccc0000c0c0c000ccccc000c000c0000ccc0000000000000000000
-- 112:000000000000c000000cc00000ccc000000cc0000000c0000000000000000000
-- 113:0000000000c0000000cc000000ccc00000cc000000c000000000000000000000
-- 114:000000000ccccc00000000000c0ccc000c0ccc000c0ccc000000000000000000
-- 115:000000000ccccc00000000000c0c0c000c0c0c000c0c0c000000000000000000
-- 116:00000000000c00000000c0000c0ccc000000c000000c00000000000000000000
-- 117:000000000cccc00000000c000c000c000c00000000cccc000000000000000000
-- 118:0000000000c00000000c00000000c000000c000000c000000000000000000000
-- 119:000000000c0c00000c0cc0000c0ccc000c0cc0000c0c00000000000000000000
-- 120:000000000ccccc000ccccc000ccccc000ccccc000ccccc000000000000000000
-- 121:0c000000cccccccc00000000000000c0cccccccc00000000000c0000cccccccc
-- 122:0000000000c000000cc0000000c0000000000000000000000000000000000000
-- 123:000000000ccc00000ccc00000ccc000000000000000000000000000000000000
-- 124:000000000c0000000cc000000c00000000000000000000000000000000000000
-- 125:000c000000ccc0000ccccc00ccccccc000000000000000000000000000000000
-- 126:ccccccc00ccccc0000ccc000000c000000000000000000000000000000000000
-- 127:000c000000cc00000ccc0000cccc00000ccc000000cc0000000c000000000000
-- 128:c0000000cc000000ccc00000cccc0000ccc00000cc000000c000000000000000
-- 129:ccc0ccc0cc0c0cc0ccc0ccc0ccc0ccc0ccc0ccc0cc0c0cc0ccc0ccc000000000
-- 130:ccccccc0ccccccc0c0ccc0c00c000c00c0ccc0c0ccccccc0ccccccc000000000
-- 131:00ccc0000c000c00c00c0c0cc000ccc0c0000c000c00000000ccc00000000000
-- 132:0ccccc00ccccccc00c0c0c000c0c0c000c0c0c000c0c0c000ccccc0000000000
-- 133:0000c000000ccc0000ccccc00ccccc00c0ccc000c00c0000ccc0000000000000
-- 134:00ccc00000ccc0000ccccc0000c0c00000c0c00000c0c000000c000000000000
-- 135:c0c0c0c000000000c00000c000000000c00000c000000000c0c0c0c000000000
-- 136:0000c00000000c00000000c00cccccccc0ccccc0c00ccc00c000c00000000000
-- 160:cccccccccceeeeeececccccccecececececcccccceceececceccccccceceecee
-- 161:cccccccceeeeeeeccccccccecececececcccccceececeececcccccceeeeceece
-- 162:cccccccccccccccccccccccccceeeeeececccccccecececececcccccceceecec
-- 163:cccccccccccccccccccccccceeeeeeeccccccccecececececcccccceececeece
-- 176:ceecccccceeeeeeeceeeeeeecceeeeeecccccccccccccccccccccccccccccccc
-- 177:cccccceeeeeeeeeeeeeeeeeeeeeeeeeccccccccccccccccccccccccccccccccc
-- 178:ceccccccceceeceeceeccccccceeeeeecccccccccccccccccccccccccccccccc
-- 179:ccccccceeeeceececccccceeeeeeeeeccccccccccccccccccccccccccccccccc
-- 192:cccccccccceeeeeececccccccecccccccecccccccecccccccecccccccecccccc
-- 193:cccccccceeeeeeccccccccecccccccecccccccecccccccecccccccecccccccec
-- 194:cccccccccceeeeeececccccccecccccccecccccccecccccececccceececcceee
-- 195:cccccccceeeeeeccccccccecccccccecccccccececcccceceecccceceeecccec
-- 196:cccccccccceeeeeececcccccceccccccceccccccceccceeececcceeececcccee
-- 197:cccccccceeeeeecccccccceccccccceccccccceceeeccceceeeccceceeccccec
-- 198:cccccccccceeeeeececccccccecccccccecccccccecccccececccceececcccee
-- 199:cccccccceeeeeecccccccceccccccceceecccceceecccceceecccceceeccccec
-- 200:cccccccccceeeeeececccccccecccccccecccceececccceececccceececcccee
-- 201:cccccccceeeeeeccccccccecccccccecccccccececcccceceecccceceeccccec
-- 202:cccccccccceeeeeececccccccecccccccecccccececccceececcceeececcccce
-- 203:cccccccceeeeeeccccccccecccccccececcccceceecccceceeecccececccccec
-- 204:ceecccccceeeeeeeceeeeeeecceeeeeecccccccccccccccccccccccccccccccc
-- 205:ccccceeceeeeeeeceeeeeeeceeeeeecccccccccccccccccccccccccccccccccc
-- 206:cccccccceeeeeeeecccccccccccccccccccccccccccccccccccccccccccccccc
-- 207:cccccccccccccccccccccccccccccccceeeeeeeeeeeeeeeeeeeeeeeecccccccc
-- 208:ceccccccceccccccceccccccceecccccceeeeeeeceeeeeeecceeeeeecccccccc
-- 209:ccccccecccccccecccccccecccccceeceeeeeeeceeeeeeeceeeeeecccccccccc
-- 210:ceccceeececcccccceccccccceecccccceeeeeeeceeeeeeecceeeeeecccccccc
-- 211:eeecccecccccccecccccccecccccceeceeeeeeeceeeeeeeceeeeeecccccccccc
-- 212:cecccccececcccccceccccccceecccccceeeeeeeceeeeeeecceeeeeecccccccc
-- 213:ecccccecccccccecccccccecccccceeceeeeeeeceeeeeeeceeeeeecccccccccc
-- 214:cecccccececcccccceccccccceecccccceeeeeeeceeeeeeecceeeeeecccccccc
-- 215:eecccceceeccccecccccccecccccceeceeeeeeeceeeeeeeceeeeeecccccccccc
-- 216:cecccceececccceececcccccceecccccceeeeeeeceeeeeeecceeeeeecccccccc
-- 217:ecccccecccccccecccccccecccccceeceeeeeeeceeeeeeeceeeeeecccccccccc
-- 218:cecccccececccccececcccccceecccccceeeeeeeceeeeeeecceeeeeecccccccc
-- 219:ecccccececccccecccccccecccccceeceeeeeeeceeeeeeeceeeeeecccccccccc
-- 220:cccccccccccccccccccccccccccccccceccccccceecccccceecccccccecccccc
-- 221:cecccccccecccccccecccccccecccccccecccccccecccccccecccccccecccccc
-- 222:ccccccecccccccecccccccecccccccecccccccecccccccecccccccecccccccec
-- 223:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
-- 224:cccccccccccccccccccccccccceeeeeececccccccecccccccecccccccecccccc
-- 225:cccccccccccccccccccccccceeeeeeccccccccecccccccecccccccecccccccec
-- 226:cccccccccccccccccccccccccceeeeeececcccccceccccccceccccccceccccce
-- 227:cccccccccccccccccccccccceeeeeeccccccccecccccccecccccccececccccec
-- 228:cccccccccccccccccccccccccceeeeeececcccccceccccccceccccccceccceee
-- 229:cccccccccccccccccccccccceeeeeecccccccceccccccceccccccceceeecccec
-- 230:cccccccccccccccccccccccccceeeeeececcccccceccccccceccccccceccccce
-- 231:cccccccccccccccccccccccceeeeeecccccccceccccccceceecccceceeccccec
-- 232:cccccccccccccccccccccccccceeeeeececccccccecccccccecccceececcccee
-- 233:cccccccccccccccccccccccceeeeeeccccccccecccccccecccccccececccccec
-- 234:cccccccccccccccccccccccccceeeeeececccccccecccccccecccccececcccee
-- 235:cccccccccccccccccccccccceeeeeeccccccccecccccccececcccceceeccccec
-- 236:ceccccccceccccccceeccccccceeeeeecccccccccccccccccccccccccccccccc
-- 237:ccccccecccccccecccccceeceeeeeecccccccccccccccccccccccccccccccccc
-- 238:cccccccccccccccccccccccceeeeeeeecccccccccccccccccccccccccccccccc
-- 239:cccccccccccccccccccccccccccccccccccccccccccccccceeeeeeeecccccccc
-- 240:ceccccccceccccccceccccccceccccccceccccccceeccccccceeeeeecccccccc
-- 241:ccccccecccccccecccccccecccccccecccccccecccccceeceeeeeecccccccccc
-- 242:cecccceececcceeececcceeececcccccceccccccceeccccccceeeeeecccccccc
-- 243:eecccceceeeccceceeecccecccccccecccccccecccccceeceeeeeecccccccccc
-- 244:ceccceeececccceececccccececcccccceccccccceeccccccceeeeeecccccccc
-- 245:eeeccceceeccccececccccecccccccecccccccecccccceeceeeeeecccccccccc
-- 246:cecccceececccceececccccececcccccceccccccceeccccccceeeeeecccccccc
-- 247:eecccceceecccceceecccceceeccccecccccccecccccceeceeeeeecccccccccc
-- 248:cecccceececccceececccceececccceececcccccceeccccccceeeeeecccccccc
-- 249:eecccceceeccccececccccecccccccecccccccecccccceeceeeeeecccccccccc
-- 250:ceccceeececccccececccccececccccececcccccceeccccccceeeeeecccccccc
-- 251:eeecccececccccececccccececccccecccccccecccccceeceeeeeecccccccccc
-- 252:cccccccccccccccccccccccccccccccccccccccccccccccceccccccccecccccc
-- </TILES>

-- <SPRITES>
-- 000:ff000000fcf00000fccf0000fcccf000fccccf00fcccf000fcffcf000f00f000
-- 001:000f000000fcf00000fcff000ffcccf0fcfccccf0fcccccf00fcccf0000fff00
-- 002:0fff0000fcccf0000fcf00000fcf00000fcf00000fcf0000fcccf0000fff0000
-- 033:00cc000000cc000000cc00000000000000cc0000000000000000000000000000
-- 034:0c0c00000c0c0000000000000000000000000000000000000000000000000000
-- 035:0c0c0000ccccc0000c0c0000ccccc0000c0c0000000000000000000000000000
-- 036:0cccc000c0c000000ccc000000c0c000cccc0000000000000000000000000000
-- 037:c000c000000c000000c000000c000000c000c000000000000000000000000000
-- 038:0c000000c0c000000cc0c000c00c00000cc0c000000000000000000000000000
-- 039:00c000000c000000000000000000000000000000000000000000000000000000
-- 040:000c000000c0000000c0000000c00000000c0000000000000000000000000000
-- 041:0c00000000c0000000c0000000c000000c000000000000000000000000000000
-- 042:00c00000c0c0c0000ccc0000c0c0c00000c00000000000000000000000000000
-- 043:0000000000c000000ccc000000c0000000000000000000000000000000000000
-- 044:0000000000000000000000000cc0000000c000000c0000000000000000000000
-- 045:00000000000000000ccc00000000000000000000000000000000000000000000
-- 046:0000000000000000000000000cc000000cc00000000000000000000000000000
-- 047:0000c000000c000000c000000c000000c0000000000000000000000000000000
-- 048:0ccc0000cc0cc000ccc0c000cc00c0000ccc0000000000000000000000000000
-- 049:00cc00000ccc000000cc000000cc00000cccc000000000000000000000000000
-- 050:cccc0000000cc0000ccc0000cc000000ccccc000000000000000000000000000
-- 051:ccccc000000cc00000cc0000c00cc0000ccc0000000000000000000000000000
-- 052:00cc00000ccc0000cc0c0000ccccc000000c0000000000000000000000000000
-- 053:ccccc000cc000000cccc0000000cc000cccc0000000000000000000000000000
-- 054:0ccc0000cc000000cccc0000cc00c0000ccc0000000000000000000000000000
-- 055:ccccc000000cc00000cc00000cc00000cc000000000000000000000000000000
-- 056:0ccc0000cc00c0000ccc0000cc00c0000ccc0000000000000000000000000000
-- 057:0ccc0000cc00c0000cccc0000000c0000ccc0000000000000000000000000000
-- 058:0cc000000cc00000000000000cc000000cc00000000000000000000000000000
-- 059:0cc000000cc00000000000000cc0000000c000000c0000000000000000000000
-- 060:000c000000c000000c00000000c00000000c0000000000000000000000000000
-- 061:000000000ccc0000000000000ccc000000000000000000000000000000000000
-- 062:0c00000000c00000000c000000c000000c000000000000000000000000000000
-- 063:0cccc000000cc00000cc00000000000000cc0000000000000000000000000000
-- 064:0ccc0000c0c0c000c0ccc000c00000000ccc0000000000000000000000000000
-- 065:0ccc0000cc00c000cc00c000ccccc000cc00c000000000000000000000000000
-- 066:cccc0000cc00c000cccc0000cc00c000cccc0000000000000000000000000000
-- 067:0ccc0000cc00c000cc000000cc00c0000ccc0000000000000000000000000000
-- 068:cccc0000cc00c000cc00c000cc00c000cccc0000000000000000000000000000
-- 069:ccccc000cc000000cccc0000cc000000ccccc000000000000000000000000000
-- 070:ccccc000cc000000cccc0000cc000000cc000000000000000000000000000000
-- 071:0cccc000cc000000cc0cc000cc00c0000cccc000000000000000000000000000
-- 072:cc00c000cc00c000ccccc000cc00c000cc00c000000000000000000000000000
-- 073:0cccc00000cc000000cc000000cc00000cccc000000000000000000000000000
-- 074:ccccc000000cc000000cc000cc0cc0000ccc0000000000000000000000000000
-- 075:cc00c000cc0c0000ccc00000cc0c0000cc00c000000000000000000000000000
-- 076:cc000000cc000000cc000000cc000000ccccc000000000000000000000000000
-- 077:cc0cc000ccccc000ccccc000c0c0c000c000c000000000000000000000000000
-- 078:cc00c000ccc0c000ccccc000cc0cc000cc00c000000000000000000000000000
-- 079:0ccc0000cc00c000cc00c000cc00c0000ccc0000000000000000000000000000
-- 080:cccc0000cc00c000cc00c000cccc0000cc000000000000000000000000000000
-- 081:0ccc0000cc00c000cc00c000cc00c0000ccc00000000c0000000000000000000
-- 082:cccc0000cc00c000cc00c000cccc0000cc00c000000000000000000000000000
-- 083:0cccc000ccc000000ccc000000ccc000cccc0000000000000000000000000000
-- 084:0cccc00000cc000000cc000000cc000000cc0000000000000000000000000000
-- 085:cc00c000cc00c000cc00c000cc00c0000ccc0000000000000000000000000000
-- 086:cc00c000cc00c000cc00c0000ccc000000c00000000000000000000000000000
-- 087:c000c000c0c0c000ccccc000ccccc000cc0cc000000000000000000000000000
-- 088:cc00c000cc00c0000ccc0000cc00c000cc00c000000000000000000000000000
-- 089:0cc0c0000cc0c0000cccc00000cc000000cc0000000000000000000000000000
-- 090:ccccc00000cc00000cc00000cc000000ccccc000000000000000000000000000
-- 091:00cc000000c0000000c0000000c0000000cc0000000000000000000000000000
-- 092:c00000000c00000000c00000000c00000000c000000000000000000000000000
-- 093:0cc0000000c0000000c0000000c000000cc00000000000000000000000000000
-- 094:00c000000c0c0000c000c0000000000000000000000000000000000000000000
-- 095:000000000000000000000000000000000cccc000000000000000000000000000
-- 096:0c00000000c00000000000000000000000000000000000000000000000000000
-- 097:000000000cccc000c00cc000c00cc0000cccc000000000000000000000000000
-- 098:cc000000cccc0000cc00c000cc00c000cccc0000000000000000000000000000
-- 099:000000000cccc000ccc00000ccc000000cccc000000000000000000000000000
-- 100:000cc0000cccc000c00cc000c00cc0000cccc000000000000000000000000000
-- 101:000000000ccc0000cc0cc000ccc000000ccc0000000000000000000000000000
-- 102:00ccc0000cc00000ccccc0000cc000000cc00000000000000000000000000000
-- 103:000000000ccc0000c00cc000ccccc000000cc0000ccc00000000000000000000
-- 104:cc000000cccc0000cc00c000cc00c000cc00c000000000000000000000000000
-- 105:00cc00000000000000cc000000cc000000cc0000000000000000000000000000
-- 106:000cc00000000000000cc000000cc000c00cc0000ccc00000000000000000000
-- 107:cc000000cc00c000cccc0000cc00c000cc00c000000000000000000000000000
-- 108:0cc000000cc000000cc000000cc0000000ccc000000000000000000000000000
-- 109:00000000cc0c0000ccccc000c0c0c000c0c0c000000000000000000000000000
-- 110:00000000cccc0000cc00c000cc00c000cc00c000000000000000000000000000
-- 111:000000000ccc0000cc00c000cc00c0000ccc0000000000000000000000000000
-- 112:00000000cccc0000cc00c000cc00c000cccc0000cc0000000000000000000000
-- 113:000000000cccc000c00cc000c00cc0000cccc000000cc0000000000000000000
-- 114:00000000cccc0000cc00c000cc000000cc000000000000000000000000000000
-- 115:000000000cccc000ccc0000000ccc000cccc0000000000000000000000000000
-- 116:0cc00000ccccc0000cc000000cc0000000ccc000000000000000000000000000
-- 117:00000000cc00c000cc00c000cc00c0000ccc0000000000000000000000000000
-- 118:00000000cc00c000cc00c0000ccc000000c00000000000000000000000000000
-- 119:00000000c000c000c0c0c000ccccc000cc0cc000000000000000000000000000
-- 120:00000000cc0cc0000ccc00000ccc0000cc0cc000000000000000000000000000
-- 121:00000000c00cc000c00cc0000cccc000000cc0000ccc00000000000000000000
-- 122:00000000ccccc00000cc00000cc00000ccccc000000000000000000000000000
-- 123:00cc000000c000000cc0000000c0000000cc0000000000000000000000000000
-- 124:00c0000000c0000000c0000000c0000000c00000000000000000000000000000
-- 125:0cc0000000c0000000cc000000c000000cc00000000000000000000000000000
-- 126:0000000000c0c0000c0c00000000000000000000000000000000000000000000
-- 161:0c0000000c0000000c000000000000000c000000000000000000000000000000
-- 162:c0c00000c0c00000000000000000000000000000000000000000000000000000
-- 163:c0c00000ccc00000c0c00000ccc00000c0c00000000000000000000000000000
-- 164:0cc00000cc0000000cc00000cc0000000c000000000000000000000000000000
-- 165:c000000000c000000c000000c000000000c00000000000000000000000000000
-- 166:cc000000cc000000ccc00000c0c000000cc00000000000000000000000000000
-- 167:0c0000000c000000000000000000000000000000000000000000000000000000
-- 168:00c000000c0000000c0000000c00000000c00000000000000000000000000000
-- 169:c00000000c0000000c0000000c000000c0000000000000000000000000000000
-- 170:00000000c0c000000c000000c0c0000000000000000000000000000000000000
-- 171:000000000c000000ccc000000c00000000000000000000000000000000000000
-- 172:000000000000000000000000000000000c000000c00000000000000000000000
-- 173:0000000000000000ccc000000000000000000000000000000000000000000000
-- 174:000000000000000000000000000000000c000000000000000000000000000000
-- 175:0000000000c000000c000000c000000000000000000000000000000000000000
-- 176:0cc00000c0c00000c0c00000c0c00000cc000000000000000000000000000000
-- 177:0c000000cc0000000c0000000c000000ccc00000000000000000000000000000
-- 178:cc00000000c000000c000000c0000000ccc00000000000000000000000000000
-- 179:cc00000000c000000c00000000c00000cc000000000000000000000000000000
-- 180:c0c00000c0c00000ccc0000000c0000000c00000000000000000000000000000
-- 181:ccc00000c0000000cc00000000c00000cc000000000000000000000000000000
-- 182:0cc00000c0000000ccc00000c0c00000ccc00000000000000000000000000000
-- 183:ccc0000000c000000c000000c0000000c0000000000000000000000000000000
-- 184:ccc00000c0c00000ccc00000c0c00000ccc00000000000000000000000000000
-- 185:ccc00000c0c00000ccc0000000c0000000c00000000000000000000000000000
-- 186:000000000c000000000000000c00000000000000000000000000000000000000
-- 187:000000000c000000000000000c000000c0000000000000000000000000000000
-- 188:00c000000c000000c00000000c00000000c00000000000000000000000000000
-- 189:00000000ccc0000000000000ccc0000000000000000000000000000000000000
-- 190:c00000000c00000000c000000c000000c0000000000000000000000000000000
-- 191:ccc0000000c000000c000000000000000c000000000000000000000000000000
-- 192:0cc00000c0c00000ccc00000c00000000cc00000000000000000000000000000
-- 193:0c000000c0c00000ccc00000c0c00000c0c00000000000000000000000000000
-- 194:cc000000c0c00000cc000000c0c00000cc000000000000000000000000000000
-- 195:0cc00000c0000000c0000000c00000000cc00000000000000000000000000000
-- 196:cc000000c0c00000c0c00000c0c00000cc000000000000000000000000000000
-- 197:ccc00000c0000000cc000000c0000000ccc00000000000000000000000000000
-- 198:ccc00000c0000000cc000000c0000000c0000000000000000000000000000000
-- 199:0cc00000c0000000c0c00000c0c000000cc00000000000000000000000000000
-- 200:c0c00000c0c00000ccc00000c0c00000c0c00000000000000000000000000000
-- 201:ccc000000c0000000c0000000c000000ccc00000000000000000000000000000
-- 202:ccc0000000c0000000c00000c0c000000c000000000000000000000000000000
-- 203:c0c00000c0c00000cc000000c0c00000c0c00000000000000000000000000000
-- 204:c0000000c0000000c0000000c0000000ccc00000000000000000000000000000
-- 205:ccc00000ccc00000c0c00000c0c00000c0c00000000000000000000000000000
-- 206:cc000000c0c00000c0c00000c0c00000c0c00000000000000000000000000000
-- 207:0c000000c0c00000c0c00000c0c000000c000000000000000000000000000000
-- 208:cc000000c0c00000cc000000c0000000c0000000000000000000000000000000
-- 209:0c000000c0c00000c0c00000ccc000000cc00000000000000000000000000000
-- 210:cc000000c0c00000ccc00000cc000000c0c00000000000000000000000000000
-- 211:0cc00000c00000000c00000000c00000cc000000000000000000000000000000
-- 212:ccc000000c0000000c0000000c0000000c000000000000000000000000000000
-- 213:c0c00000c0c00000c0c00000c0c000000cc00000000000000000000000000000
-- 214:c0c00000c0c00000c0c00000c0c000000c000000000000000000000000000000
-- 215:c0c00000c0c00000c0c00000ccc00000ccc00000000000000000000000000000
-- 216:c0c00000c0c000000c000000c0c00000c0c00000000000000000000000000000
-- 217:c0c00000c0c000000c0000000c0000000c000000000000000000000000000000
-- 218:ccc0000000c000000c000000c0000000ccc00000000000000000000000000000
-- 219:0cc000000c0000000c0000000c0000000cc00000000000000000000000000000
-- 220:00000000c00000000c00000000c0000000000000000000000000000000000000
-- 221:cc0000000c0000000c0000000c000000cc000000000000000000000000000000
-- 222:0c000000c0c00000000000000000000000000000000000000000000000000000
-- 223:00000000000000000000000000000000ccc00000000000000000000000000000
-- 224:0c00000000c00000000000000000000000000000000000000000000000000000
-- 225:00000000cc0000000cc00000c0c00000ccc00000000000000000000000000000
-- 226:c0000000cc000000c0c00000c0c00000cc000000000000000000000000000000
-- 227:000000000cc00000c0000000c00000000cc00000000000000000000000000000
-- 228:00c000000cc00000c0c00000c0c000000cc00000000000000000000000000000
-- 229:000000000cc00000c0c00000cc0000000cc00000000000000000000000000000
-- 230:00c000000c000000ccc000000c0000000c000000000000000000000000000000
-- 231:000000000cc00000c0c00000ccc0000000c000000c0000000000000000000000
-- 232:c0000000cc000000c0c00000c0c00000c0c00000000000000000000000000000
-- 233:0c000000000000000c0000000c0000000c000000000000000000000000000000
-- 234:00c000000000000000c0000000c00000c0c000000c0000000000000000000000
-- 235:c0000000c0c00000cc000000cc000000c0c00000000000000000000000000000
-- 236:cc0000000c0000000c0000000c000000ccc00000000000000000000000000000
-- 237:00000000ccc00000ccc00000c0c00000c0c00000000000000000000000000000
-- 238:00000000cc000000c0c00000c0c00000c0c00000000000000000000000000000
-- 239:000000000c000000c0c00000c0c000000c000000000000000000000000000000
-- 240:00000000cc000000c0c00000c0c00000cc000000c00000000000000000000000
-- 241:000000000cc00000c0c00000c0c000000cc0000000c000000000000000000000
-- 242:00000000c0c00000cc000000c0000000c0000000000000000000000000000000
-- 243:000000000cc00000cc00000000c00000cc000000000000000000000000000000
-- 244:0c000000ccc000000c0000000c00000000c00000000000000000000000000000
-- 245:00000000c0c00000c0c00000c0c000000cc00000000000000000000000000000
-- 246:00000000c0c00000c0c00000c0c000000c000000000000000000000000000000
-- 247:00000000c0c00000c0c00000ccc00000ccc00000000000000000000000000000
-- 248:00000000c0c000000c000000c0c00000c0c00000000000000000000000000000
-- 249:00000000c0c00000c0c000000cc0000000c000000c0000000000000000000000
-- 250:00000000ccc000000cc00000c0000000ccc00000000000000000000000000000
-- 251:0cc000000c000000cc0000000c0000000cc00000000000000000000000000000
-- 252:0c0000000c000000000000000c0000000c000000000000000000000000000000
-- 253:cc0000000c0000000cc000000c000000cc000000000000000000000000000000
-- 254:000000000cc00000cc0000000000000000000000000000000000000000000000
-- </SPRITES>

-- <MAP>
-- 000:0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:ccdcccdcccdcccdcccdcccdcccdcccdcccdcccdcccdccedecedecedecedecedecedecedecedecedecedecede00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1dccdcccdc0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1fcedecede00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:fd0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0cec1cfd0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0eee1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:fd0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0dcdedfd0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0fcfed00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:acbc0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1c0c1cddedaebe0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1e0e1edded00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:adbd0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1dafbf0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f0f1f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:0cec1c0cec1c0cecececececececec1cfdfdfdfdfdfd0eee1e0eee1e0eeeeeeeeeeeeeeeee1efdfdfdfdfdfd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:0dfc1d0dfc1d0dfcfcfcfcfcfcfcfc1dfdfd2c3cfdfd0ffe1f0ffe1f0ffefefefefefefefe1ffdfd2e3efdfd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:fdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfd2d3dfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfdfd2f3ffdfd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:fd0a1afdfdfdfdfdfdfdfdfdfdfdfdfd6c7c4c5c8c9cfd2a3afdfdfdfdfdfdfdfdfdfdfdfdfd6e7e4e5e8e9e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:fd0b1bfdfdfdfdfdfdfdfdfdfdfdfdfd6d7d4d5d8d9dfd2b3bfdfdfdfdfdfdfdfdfdfdfdfdfd6f7f4f5f8f9f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:500050005000f090f090f090b090b090b090f090f090f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000200000000000
-- 001:30003000304030403070307030c030c090009000900090009000900090009000c000c000c000c000c000c000c000c000f000f000f000f000f000f000302000000800
-- 002:e000e010e010f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000400000000000
-- </SFX>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

