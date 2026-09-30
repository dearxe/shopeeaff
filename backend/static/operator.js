'use strict';
const byId = id => document.getElementById(id);
let csrf = null;
let timer = null;
let pending = null;
try{pending=JSON.parse(localStorage.getItem('affiliatehelper-pending-local-job')||'null');}catch{message('อ่านคำขอที่ค้างในเบราว์เซอร์ไม่ได้ กรุณาตรวจคิวก่อนสร้างงานใหม่',true);}
const statusLabels = {queued:'รอคิว',processing:'ตรวจปลายทาง',waiting_for_operator:'รอผู้ดูแลสร้างลิงก์',completed:'สำเร็จ',failed:'ไม่สำเร็จ'};
function message(text, error=false){byId('message').textContent=text;byId('message').className=error?'error':'success';}
async function api(path,method='GET',body,extraHeaders={}){
  const headers={...extraHeaders};if(body!==undefined)headers['Content-Type']='application/json';if(csrf)headers['X-CSRF-Token']=csrf;
  const response=await fetch(path,{method,headers,body:body===undefined?undefined:JSON.stringify(body),credentials:'same-origin',cache:'no-store'});
  const value=await response.json();
  if(!response.ok){if(response.status===401)showLogin();const error=new Error(value.error?.message||'เชื่อมต่อ Backend ไม่สำเร็จ');error.status=response.status;throw error;}
  return value;
}
function showLogin(){csrf=null;clearTimeout(timer);byId('login-panel').hidden=false;byId('dashboard').hidden=true;}
function showDashboard(){byId('login-panel').hidden=true;byId('dashboard').hidden=false;}
function element(tag,text,className){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(className)node.className=className;return node;}
function input(label,type='url',value=''){const wrapper=element('label',label);const field=element('input');field.type=type;field.value=value;field.required=true;wrapper.append(field);return [wrapper,field];}
function checkbox(text){const wrapper=element('label',undefined,'checkbox');const field=element('input');field.type='checkbox';field.required=true;wrapper.append(field,element('span',text));return [wrapper,field];}
function render(job){
  const card=element('article',undefined,'card');card.append(element('span',statusLabels[job.status]||job.status,'status'));
  card.append(element('p',job.jobId+' • '+new Date(job.createdAt).toLocaleString('th-TH'),'meta'));
  if(job.tracking)card.append(element('p','ช่องทาง: '+job.tracking.channel+' • prefix: '+job.tracking.subIdPrefixes.join(', '),'meta'));
  const source=element('a','เปิดลิงก์ต้นฉบับเพื่อตรวจสินค้า');source.href=job.originalUrl;source.target='_blank';source.rel='noopener noreferrer';card.append(source);
  card.append(element('p',job.originalUrl,'meta'));
  if(job.error)card.append(element('p',job.error.message,'error'));
  if(job.affiliateUrl){card.append(element('p','ผลลัพธ์จริง: '+job.affiliateUrl,'result'));return card;}
  if(job.status!=='waiting_for_operator')return card;
  const form=element('form');
  const [productLabel,product]=input('URL สินค้าฉบับเต็มที่ตรวจแล้ว (shopee.co.th/...-i.shopId.itemId)', 'url',job.resolvedUrl||'');
  const [affiliateLabel,affiliate]=input('Affiliate URL ที่สร้างจากหน้า Shopee ของบัญชีเจ้าของ');
  const [verifiedLabel,verified]=checkbox('ตรวจในเบราว์เซอร์แล้วว่าลิงก์ต้นฉบับและ Affiliate ชี้ไปสินค้ารายการเดียวกัน');
  const [ownerLabel,owner]=checkbox('สร้างลิงก์นี้จากบัญชี Affiliate 15349870042 ของเจ้าของระบบจริง ไม่ใช่การเติมพารามิเตอร์เอง');
  const save=element('button','บันทึกผลจริง');save.type='submit';form.append(productLabel,affiliateLabel,verifiedLabel,ownerLabel,save);
  form.addEventListener('submit',async event=>{event.preventDefault();save.disabled=true;try{
    const result=await api('/operator/jobs/'+encodeURIComponent(job.jobId)+'/complete','POST',{affiliateUrl:affiliate.value,verifiedProductUrl:product.value,destinationVerified:verified.checked,ownershipConfirmed:owner.checked});
    message(result.verification==='network_verified'?'บันทึกผลสำเร็จแล้ว':'บันทึกผลจริงโดยอาศัยการตรวจยืนยันของผู้ดูแล (เว็บสินค้าบล็อกการตรวจอัตโนมัติ)');await refresh();
  }catch(error){message(error.message,true);}finally{save.disabled=false;}});
  card.append(form);
  const details=element('details');details.append(element('summary','ทำเครื่องหมายว่าไม่สำเร็จ'));
  const failForm=element('form');const [reasonLabel,reason]=input('เหตุผล','text');const fail=element('button','จบงานเป็นไม่สำเร็จ');fail.type='submit';fail.className='secondary';failForm.append(reasonLabel,fail);
  failForm.addEventListener('submit',async event=>{event.preventDefault();fail.disabled=true;try{await api('/operator/jobs/'+encodeURIComponent(job.jobId)+'/fail','POST',{message:reason.value});message('บันทึกว่าไม่สำเร็จแล้ว');await refresh();}catch(error){message(error.message,true);}finally{fail.disabled=false;}});
  details.append(failForm);card.append(details);return card;
}
async function refresh(){
  clearTimeout(timer);if(!csrf)return;
  try{const value=await api('/operator/jobs');byId('worker-label').textContent=value.workerStatus==='offline'?'ตัวตรวจคิวออฟไลน์':'ระบบรับคิวทำงาน • รอผู้ดูแลสร้าง Affiliate จริง';byId('owner-label').textContent='บัญชีเจ้าของ: '+value.ownerAffiliateId+' • หน้าผู้ดูแลใช้ได้เฉพาะ PC นี้';
    // Do not replace a form while the operator is entering a result.
    if(!byId('jobs').contains(document.activeElement)){byId('jobs').replaceChildren();if(!value.jobs.length)byId('jobs').append(element('article','ยังไม่มีงาน รอคำขอจากแอปหรือทดสอบ API','card'));else value.jobs.forEach(job=>byId('jobs').append(render(job)));}
  }catch(error){message(error.message,true);}finally{if(csrf&&!document.hidden)timer=setTimeout(refresh,5000);}
}
byId('login-form').addEventListener('submit',async event=>{event.preventDefault();const button=event.currentTarget.querySelector('button');button.disabled=true;try{const value=await api('/operator/login','POST',{code:byId('access-code').value});byId('access-code').value='';csrf=value.csrfToken;showDashboard();message('เข้าสู่ระบบแล้ว');await refresh();}catch(error){message(error.message,true);}finally{button.disabled=false;}});
byId('refresh').addEventListener('click',refresh);
function pendingNotice(){byId('pending-note').textContent=pending?'มีคำขอที่ยังไม่ทราบผล กดส่งเข้าคิวอีกครั้งเพื่อ retry คำขอเดิมด้วย key เดิม':'';}
pendingNotice();
byId('create-form').addEventListener('submit',async event=>{event.preventDefault();const button=byId('create-button');button.disabled=true;try{
  if(!pending){pending={key:crypto.randomUUID(),body:{clientRequestId:crypto.randomUUID(),originalUrl:byId('product-source').value,tracking:{channel:byId('share-channel').value,subIdPrefixes:['ios','affiliate','shop']}}};localStorage.setItem('affiliatehelper-pending-local-job',JSON.stringify(pending));}
  const value=await api('/operator/test-jobs','POST',pending.body,{'Idempotency-Key':pending.key});pending=null;localStorage.removeItem('affiliatehelper-pending-local-job');byId('product-source').value='';pendingNotice();message('รับงานแล้ว: '+value.jobId);await refresh();
}catch(error){if([400,413,415].includes(error.status)){pending=null;localStorage.removeItem('affiliatehelper-pending-local-job');}pendingNotice();message(error.message+' • ถ้ายังไม่ทราบว่ารับงานหรือไม่ ให้ลองคำขอเดิมอีกครั้ง',true);}finally{button.disabled=false;}});
byId('logout').addEventListener('click',async()=>{try{await api('/operator/logout','POST',{});showLogin();message('ออกจากระบบแล้ว');}catch(error){message(error.message,true);}});
document.addEventListener('visibilitychange',()=>{if(document.hidden)clearTimeout(timer);else refresh();});
(async()=>{try{const value=await api('/operator/session');csrf=value.csrfToken;showDashboard();await refresh();}catch{showLogin();}})();
