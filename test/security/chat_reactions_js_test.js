const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
function element(values = {}) {
  return Object.assign({ events: {}, addEventListener(n,f) { this.events[n]=f; }, removeEventListener(n) { delete this.events[n]; },
    focus() { this.focused=true; }, setAttribute(n,v) { this[n]=v; }, removeAttribute(n) { delete this[n]; }
  },values);
}
const summary = element();
const picker = element({ open:false, querySelector: () => summary, contains: target => target === summary });
summary.parentElement=picker;
summary.closest = selector => selector === '.chat-reactions__picker > summary' ? summary : null;
const status = element({ textContent:'' });
const buttons = [element({value:'thanks'}),element({value:''})];
const form = element({ action:'/conversations/local/messages/1/reaction',
  closest: selector => selector === '[data-chat-reaction-form]' ? form : wrapper,
  querySelector: () => ({ value:'per-form-token' }), querySelectorAll: () => buttons
});
const wrapper=element({id:'chat-reactions-1', querySelector: () => status});
const updated=element({querySelector: selector => selector === 'summary' ? summary : status});
let reports=[];
const thread=element({contains: () => true,querySelectorAll: () => reports.filter(report => report.open)});
const document=element({readyState:'loading', body:{contains:()=>true}, getElementById:id=>id==='chat-messages'?thread:updated});
const window=element();
let nativeWatcher;
window.CloseWatcher = function () { nativeWatcher=this; this.addEventListener=(name,fn)=>this.close=fn; this.destroy=()=>this.destroyed=true; };
let requests=[], finish;
const fetch=(url,options)=>{requests.push({url,options});return new Promise(resolve=>finish=resolve);};
vm.runInNewContext(fs.readFileSync(__dirname+'/../../app/assets/javascripts/chat_reactions.js','utf8'),{document,window,fetch});
document.events.DOMContentLoaded();
function click(target){document.events.click({target,preventDefault(){this.prevented=true;}});}
function submit(choice){ const event={target:form,submitter:choice,preventDefault(){this.prevented=true;}};thread.events.submit(event);assert(event.prevented); }
async function flush(){for(let i=0;i<10;i++)await Promise.resolve();}
(async()=>{
  click(summary);assert(picker.open);
  click(summary);assert(!picker.open);
  click(summary);document.events.keydown({key:'Escape',preventDefault(){}});assert(!picker.open);assert(summary.focused);
  click(summary);nativeWatcher.close();assert(!picker.open);assert(nativeWatcher.destroyed);
  click(summary);click({closest:()=>null});assert(!picker.open);
  const report=element({open:true,contains:()=>false});reports=[report];
  click(summary);assert(!report.open,'opening reactions closes the report panel without resetting its form');
  report.open=true;document.events.keydown({key:'Escape',preventDefault(){}});assert(!report.open);
  report.open=true;click({closest:()=>null});assert(!report.open,'outside click closes the report popup');
  click(summary);submit(buttons[0]);submit(buttons[0]);assert.equal(requests.length,1,'repeated taps must not send concurrent mutations');
  assert.equal(requests[0].options.method,'PUT');assert.equal(requests[0].options.headers['X-CSRF-Token'],'per-form-token');
  assert.equal(JSON.parse(requests[0].options.body).reaction.key,'thanks');
  finish({ok:true,redirected:false,json:async()=>({html:'<div>updated</div>'})});await flush();assert.equal(wrapper.outerHTML,'<div>updated</div>');assert.equal(status.textContent,'リアクションを保存しました。');
  submit(buttons[1]);assert.equal(JSON.parse(requests[1].options.body).reaction.key,'','removal sends an idempotent empty desired state');
  finish({ok:false,status:422,json:async()=>({error:'ブロック中です。'})});await flush();assert.equal(status.textContent,'ブロック中です。');assert.equal(status['data-error'],'true');assert(buttons.every(b=>!b.disabled));
  submit(buttons[0]);finish({ok:true,redirected:true});await flush();assert(status.textContent.includes('ログイン状態'));assert(buttons.every(b=>!b.disabled));
  submit(buttons[1]);finish({ok:true,json:async()=>({html:'removed'})});await flush();assert.equal(status.textContent,'リアクションを取り消しました。');
  document.events['turbolinks:before-cache']();assert(!document.events.click);assert(!thread.events.submit);
  console.log('chat reactions: selection, dismissal, native Back, repeated taps, CSRF, retry/error and cleanup passed');
})().catch(error=>{console.error(error);process.exit(1);});
